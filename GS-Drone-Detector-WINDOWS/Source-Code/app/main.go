package main

import (
 "bytes"
 "embed"
 "encoding/csv"
 "encoding/json"
  "io"
 "log"
 "net"
 "net/http"
 "os/exec"
 "context"
 "syscall"
  "regexp"
 "runtime"
 "strconv"
 "strings"
 "sync"
 "sync/atomic"
 "time"
)

//go:embed web/*
var website embed.FS

type Device struct { Name string `json:"name"`; BSSID string `json:"bssid"`; Signal int `json:"signal"`; Channel string `json:"channel"`; Evidence string `json:"evidence"`; Seen string `json:"seen"`; Level string `json:"level"` }
type Engine struct { sync.Mutex; active bool; matches map[string]Device; scans int; lastScan string; lastErr string; started string }
var engine = &Engine{ matches: map[string]Device{} }
var ssidRE = regexp.MustCompile(`(?i)^\s*SSID\s+\d+\s*:\s*(.*)$`)
var bssidRE = regexp.MustCompile(`(?i)^\s*BSSID\s+\d+\s*:\s*(.*)$`)
var signalRE = regexp.MustCompile(`(?i)^\s*Signal\s*:\s*(\d+)\s*%`)
var channelRE = regexp.MustCompile(`(?i)^\s*Channel\s*:\s*(.*)$`)
var keywords = []string{"DJI", "MAVIC", "MATRICE", "PHANTOM", "AVATA", "TELLO", "PARROT", "ANAFI", "SKYDIO", "AUTEL", "HOLY STONE", "HOLYSTONE", "POTENSIC", "HUBSAN", "BETAFPV", "FIMI", "EMAX", "FPV"}
func evidence(s string) string { u:=strings.ToUpper(strings.TrimSpace(s)); if strings.HasPrefix(u,"RID-") { return "SSID Remote ID naming clue (unverified)" }; for _, k:= range keywords { if strings.Contains(u,k) { return "SSID name matches "+k } }; return "" }
func strength(n int) string { if n>=90{return "STRONG"}; if n>=50{return "MODERATE"};return "WEAK" }
func parseWiFi(text string) []Device { out:=[]Device{}; ssid:=""; bssid:=""; sig:=0; channel:=""
 flush:=func(){ if bssid!="" { if ev:=evidence(ssid);ev!="" { out=append(out, Device{Name:ssid,BSSID:bssid,Signal:sig,Channel:channel,Evidence:ev,Seen:time.Now().Format("15:04:05"),Level:strength(sig)}) } } }
 for _,line:=range strings.Split(text,"\n") { if m:=ssidRE.FindStringSubmatch(line);m!=nil { flush();ssid=strings.TrimSpace(m[1]);bssid="";sig=0;channel="" } else if m:=bssidRE.FindStringSubmatch(line);m!=nil { flush();bssid=strings.TrimSpace(m[1]);sig=0;channel="" } else if m:=signalRE.FindStringSubmatch(line);m!=nil { sig,_=strconv.Atoi(m[1]) } else if m:=channelRE.FindStringSubmatch(line);m!=nil {channel=strings.TrimSpace(m[1])} };flush();return out
}
func takeScan(scanCtx context.Context) { if runtime.GOOS!="windows" {engine.Lock();engine.lastErr="Windows Wi-Fi scanning requires Windows";engine.Unlock();return}; ctx,cancel:=context.WithTimeout(scanCtx,6*time.Second);defer cancel();cmd:=exec.CommandContext(ctx,"netsh","wlan","show","networks","mode=bssid");cmd.SysProcAttr=&syscall.SysProcAttr{HideWindow:true}; var stderr bytes.Buffer;cmd.Stderr=&stderr; b,err:=cmd.Output();engine.Lock();defer engine.Unlock();engine.scans++;engine.lastScan=time.Now().Format("15:04:05");if err!=nil {engine.lastErr=strings.TrimSpace(stderr.String());if engine.lastErr==""{engine.lastErr=err.Error()};return};engine.lastErr="";for _,d:=range parseWiFi(string(b)) { engine.matches[d.BSSID]=d } }
var scanCancel context.CancelFunc
func stopScanning() {
 engine.Lock()
 engine.active=false
 if scanCancel!=nil {scanCancel();scanCancel=nil}
 engine.Unlock()
}
func scanLoop(ctx context.Context) {
 for {
  if ctx.Err()!=nil {return}
  takeScan(ctx)
  select {case <-ctx.Done():return;case <-time.After(2*time.Second):}
 }
}
func jsonResponse(w http.ResponseWriter,v any){ w.Header().Set("Content-Type","application/json");w.Header().Set("Cache-Control","no-store");_ = json.NewEncoder(w).Encode(v) }
func localOnly(next http.Handler) http.Handler {return http.HandlerFunc(func(w http.ResponseWriter,r *http.Request){ host,_,err:=net.SplitHostPort(r.RemoteAddr);if err!=nil|| net.ParseIP(host)==nil||!net.ParseIP(host).IsLoopback(){http.Error(w,"local only",403);return};next.ServeHTTP(w,r)})}
func main(){ mux:=http.NewServeMux(); quitRequested:=make(chan struct{},1)
 // A browser tab owns this receiver: if the tab closes, the backend must exit.
 // Last-contact watchdog also covers browser crashes and laptops sleeping.
 var lastHeartbeat atomic.Int64
 var dashboardSeen atomic.Bool
 signalQuit:=func(){select{case quitRequested<-struct{}{}:default:}}
 mux.HandleFunc("/api/heartbeat",func(w http.ResponseWriter,r *http.Request){
   if r.Method!="POST" {http.Error(w,"method",405);return}
   lastHeartbeat.Store(time.Now().UnixNano());dashboardSeen.Store(true)
   jsonResponse(w,map[string]bool{"ok":true})
 })
 mux.HandleFunc("/api/browser-closed",func(w http.ResponseWriter,r *http.Request){
   if r.Method!="POST" {http.Error(w,"method",405);return}
   w.WriteHeader(http.StatusNoContent)
   signalQuit()
 })
 go func(){ticker:=time.NewTicker(2*time.Second);defer ticker.Stop();for range ticker.C {
   if dashboardSeen.Load() && time.Since(time.Unix(0,lastHeartbeat.Load()))>8*time.Second {signalQuit();return}
 }}()
 mux.HandleFunc("/api/status",func(w http.ResponseWriter,r *http.Request){engine.Lock();defer engine.Unlock(); list:=[]Device{}; strong:=0;for _,d:=range engine.matches {list=append(list,d);if d.Level=="STRONG"{strong++}};jsonResponse(w,map[string]any{"active":engine.active,"matches":list,"count":len(list),"strong":strong,"scans":engine.scans,"lastScan":engine.lastScan,"lastError":engine.lastErr,"started":engine.started,"mode":"Quiet Wi-Fi scanning • 2 sec target"})})
 mux.HandleFunc("/api/scan",func(w http.ResponseWriter,r *http.Request){if r.Method!="POST" {http.Error(w,"method",405);return};a:=r.URL.Query().Get("mode");engine.Lock();switch a {case "start":if !engine.active{ctx,cancel:=context.WithCancel(context.Background());scanCancel=cancel;engine.active=true;engine.started=time.Now().Format("15:04:05");go scanLoop(ctx)};case "stop":engine.active=false;if scanCancel!=nil {scanCancel();scanCancel=nil};case "clear":engine.matches=map[string]Device{};engine.lastErr="";default:engine.Unlock();http.Error(w,"invalid mode",400);return};engine.Unlock();jsonResponse(w,map[string]string{"result":"ok"})})
 mux.HandleFunc("/api/quit",func(w http.ResponseWriter,r *http.Request){
  if r.Method!="POST"{http.Error(w,"method",405);return}
  stopScanning()
  jsonResponse(w,map[string]string{"ok":"true"})
  if f,ok:=w.(http.Flusher);ok {f.Flush()}
  select {case quitRequested<-struct{}{}:default:}
 })
 mux.HandleFunc("/api/export",func(w http.ResponseWriter,r *http.Request){engine.Lock();list:=make([]Device,0,len(engine.matches));for _,d:=range engine.matches{list=append(list,d)};engine.Unlock();w.Header().Set("Content-Type","text/csv; charset=utf-8");w.Header().Set("Content-Disposition","attachment; filename=gs-drone-detector-results.csv");c:=csv.NewWriter(w);_ = c.Write([]string{"Name","BSSID","Signal %","Level","Channel","Evidence","Last seen"});for _,d:=range list{_ =c.Write([]string{d.Name,d.BSSID,strconv.Itoa(d.Signal),d.Level,d.Channel,d.Evidence,d.Seen})};c.Flush()})
 mux.HandleFunc("/",func(w http.ResponseWriter,r *http.Request){p:=r.URL.Path;if p=="/"{p="/index.html"};f,err:=website.Open("web"+p);if err!=nil{http.NotFound(w,r);return};defer f.Close();if strings.HasSuffix(p,".png"){w.Header().Set("Content-Type","image/png")};if strings.HasSuffix(p,".css"){w.Header().Set("Content-Type","text/css")};if strings.HasSuffix(p,".js"){w.Header().Set("Content-Type","text/javascript")};w.Header().Set("Cache-Control","max-age=3600");_,_=io.Copy(w,f)})
 listener,err:=net.Listen("tcp","127.0.0.1:0");if err!=nil{log.Fatal(err)};addr:="http://"+listener.Addr().String();go func(){time.Sleep(600*time.Millisecond);if runtime.GOOS=="windows" {cmd:=exec.Command("rundll32","url.dll,FileProtocolHandler",addr);_ =cmd.Start()} else { _ = exec.Command("xdg-open",addr).Start() }}();server:=&http.Server{Handler:localOnly(mux)}
 go func(){err:=server.Serve(listener);if err!=nil && err!=http.ErrServerClosed {log.Printf("server: %v",err);select{case quitRequested<-struct{}{}:default:}}}()
 <-quitRequested
 stopScanning()
 shutdownCtx,shutdownCancel:=context.WithTimeout(context.Background(),2*time.Second)
 defer shutdownCancel()
 _=server.Shutdown(shutdownCtx)
 // Returning from main ends any in-flight scanning goroutines.
}

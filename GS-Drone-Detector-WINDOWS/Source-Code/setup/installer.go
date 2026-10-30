package main
import (
 "embed"
 "fmt"
 "encoding/json"
 "io"
 "net"
 "net/http"
 "os"
 "os/exec"
 "syscall"
 "path/filepath"
 "runtime"
 "time"
 "strings"
 "context"
 "sync/atomic"
)
//go:embed GS-Drone-Detector.exe brand.png icon.ico
var payload embed.FS
func appDir() string {p:=os.Getenv("LOCALAPPDATA"); if p=="" {p=os.TempDir()};return filepath.Join(p,"Programs","GhostStrats","GS Drone Detector")}
func psQuote(v string) string {return "'" + strings.ReplaceAll(v,"'","''") + "'"}
func link(shortcut,exe string) error {
 script:=`$ErrorActionPreference='Stop'; $w=New-Object -ComObject WScript.Shell; $s=$w.CreateShortcut(`+psQuote(shortcut)+`); $s.TargetPath=`+psQuote(exe)+`; $s.WorkingDirectory=Split-Path `+psQuote(exe)+`; $s.IconLocation=`+psQuote(filepath.Join(filepath.Dir(exe),"icon.ico"))+`; $s.Save()`
 cmd:=exec.Command("powershell.exe","-NoProfile","-NonInteractive","-Command",script)
 cmd.SysProcAttr=&syscall.SysProcAttr{HideWindow:true}
 output,err:=cmd.CombinedOutput()
 if err!=nil{return fmt.Errorf("shortcut: %v (%s)",err,strings.TrimSpace(string(output)))}
 return nil
}
func desktopDir() string {
 cmd:=exec.Command("powershell.exe","-NoProfile","-NonInteractive","-Command",`[Environment]::GetFolderPath('DesktopDirectory')`)
 cmd.SysProcAttr=&syscall.SysProcAttr{HideWindow:true}
 if out,err:=cmd.Output();err==nil{p:=strings.TrimSpace(string(out));if p!=""{return p}}
 p:=filepath.Join(os.Getenv("USERPROFILE"),"Desktop")
 if _,err:=os.Stat(p);err==nil{return p}
 return ""
}
var installationWarnings string
func install(desktop bool) error {installationWarnings="";dir:=appDir();if err:=os.MkdirAll(dir,0755);err!=nil{return err}; b,err:=payload.ReadFile("GS-Drone-Detector.exe");if err!=nil{return err};app:=filepath.Join(dir,"GS-Drone-Detector.exe");if err:=os.WriteFile(app,b,0755);err!=nil{return err}; icon,err:=payload.ReadFile("icon.ico");if err!=nil{return err};if err:=os.WriteFile(filepath.Join(dir,"icon.ico"),icon,0644);err!=nil{return err};self,err:=os.Executable();if err!=nil{return err};uninstall:=filepath.Join(dir,"GS-Drone-Detector-Uninstall.exe");if err:=copyFile(self,uninstall);err!=nil{return err};menu:=filepath.Join(os.Getenv("APPDATA"),"Microsoft","Windows","Start Menu","Programs","GhostStrats");_ =os.MkdirAll(menu,0755);shortcutError:=""
 if err:=link(filepath.Join(menu,"GS Drone Detector.lnk"),app);err!=nil{shortcutError="Start Menu shortcut: "+err.Error()}
 if desktop {if d:=desktopDir();d!="" {if err:=link(filepath.Join(d,"GS Drone Detector.lnk"),app);err!=nil{shortcutError+=" Desktop shortcut: "+err.Error()}}}
key:=`HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\GSDroneDetector`;_ =exec.Command("reg","add",key,"/f","/v","DisplayName","/t","REG_SZ","/d","GS Drone Detector").Run();_ =exec.Command("reg","add",key,"/f","/v","DisplayVersion","/t","REG_SZ","/d","0.9 Beta").Run();_ =exec.Command("reg","add",key,"/f","/v","Publisher","/t","REG_SZ","/d","GhostStrats LLC").Run();_ =exec.Command("reg","add",key,"/f","/v","UninstallString","/t","REG_SZ","/d",`"`+uninstall+`" --uninstall`).Run();_ =exec.Command("reg","add",key,"/f","/v","DisplayIcon","/t","REG_SZ","/d",filepath.Join(dir,"icon.ico")).Run();installationWarnings=shortcutError;return nil}
func copyFile(src,dst string) error{r,err:=os.Open(src);if err!=nil{return err};defer r.Close();w,err:=os.Create(dst);if err!=nil{return err};defer w.Close();_,err=io.Copy(w,r);return err}
func uninstall(){dir:=appDir();_ =os.Remove(filepath.Join(os.Getenv("APPDATA"),"Microsoft","Windows","Start Menu","Programs","GhostStrats","GS Drone Detector.lnk"));if d:=desktopDir();d!="" {_=os.Remove(filepath.Join(d,"GS Drone Detector.lnk"))};_ =exec.Command("reg","delete",`HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\GSDroneDetector`,"/f").Run();_ =os.Remove(filepath.Join(dir,"GS-Drone-Detector.exe"));_ =exec.Command("cmd","/c","start","","/min","cmd","/c","timeout /t 2 /nobreak >nul & del /q \""+filepath.Join(dir,"GS-Drone-Detector-Uninstall.exe")+"\" & rmdir \""+dir+"\"").Start()}
func page() string {return `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>GhostStrats Setup</title><style>*{box-sizing:border-box}body{margin:0;background:#08070d;color:#f5edff;font-family:Segoe UI,Arial,sans-serif}.wrap{width:min(930px,94vw);margin:4vh auto;border:1px solid #513963;border-radius:24px;overflow:hidden;background:#161020;box-shadow:0 25px 120px #000c}.hero{height:310px;background:linear-gradient(90deg,rgba(7,6,13,.90),rgba(7,6,13,.46) 55%,rgba(7,6,13,.05)),url('/brand.png') 50% 43%/cover;position:relative;padding:50px 50px}.hero:after{content:"";height:4px;position:absolute;bottom:0;left:0;right:0;background:linear-gradient(90deg,#b47eff,transparent)}.kicker{font-size:12px;letter-spacing:3px;color:#cdacff;font-weight:800}h1{margin:18px 0 12px;font-size:52px;letter-spacing:-2px;line-height:1}h1 em{font-style:normal;color:#be88ff}.hero p{color:#d6c9e0}.body{padding:34px 50px 42px}h2{font-size:18px}p{color:#c3b5d1;line-height:1.7}.path{margin-top:18px;padding:17px;background:#241c31;border:1px solid #433351;border-radius:12px;font:12px Consolas,monospace;color:#dacbef;overflow-wrap:anywhere}.check{display:flex;gap:12px;align-items:center;margin:24px 0;color:#e1d3ea}input{accent-color:#b57bff;width:18px;height:18px}button{background:linear-gradient(110deg,#7648cb,#bf80f2);border:1px solid #d5a0ff;color:white;font:bold 13px Segoe UI,Arial,sans-serif;letter-spacing:1px;border-radius:11px;padding:16px 28px;cursor:pointer}button:disabled{opacity:.5;cursor:wait}.bottom{display:flex;justify-content:space-between;gap:18px;align-items:center;flex-wrap:wrap}#status{font-size:13px;color:#bdcba9}small{color:#90849f}@media(max-width:600px){.hero{padding:35px 25px;height:280px}h1{font-size:39px}.body{padding:25px}}</style></head><body><div class="wrap"><section class="hero"><div class="kicker">GHOSTSTRATS // WINDOWS SETUP</div><h1>GS <em>DRONE</em><br>DETECTOR</h1><p>Passive signal awareness • Version 0.9 Beta</p></section><section class="body"><h2>Install GS Drone Detector</h2><p>This installer sets up the standalone Windows application, adds a Start Menu shortcut, and registers an uninstaller in Windows Apps &amp; Features. Everything needed to run the app is included. If shortcut creation is blocked, open the application directly from its installation folder.</p><div class="path" id="path">Current user installation · %LOCALAPPDATA%\Programs\GhostStrats\GS Drone Detector</div><label class="check"><input id="desktop" type="checkbox" checked> Create desktop shortcut</label><div class="bottom"><button id="install" onclick="run()">INSTALL APPLICATION →</button><button id="exit" onclick="quitSetup()" style="background:#342844">CLOSE SETUP</button><span id="status">READY TO INSTALL</span></div><p><small>GHOSTSTRATS LLC · SAFETY IS AN ILLUSION · Windows 10/11 x64</small></p></section></div><script>
let completed=false;
const ping=setInterval(()=>{fetch('/api/heartbeat',{method:'POST',keepalive:true}).catch(()=>clearInterval(ping))},1500);
function quitSetup(){clearInterval(ping);navigator.sendBeacon('/api/quit','');document.getElementById('status').textContent='SETUP CLOSED. You can close this tab.';document.getElementById('install').disabled=true;document.getElementById('exit').disabled=true;window.close();}
window.addEventListener('pagehide',()=>{clearInterval(ping);navigator.sendBeacon('/api/quit','')});
async function run(){const b=document.getElementById('install'),s=document.getElementById('status');b.disabled=true;s.textContent='INSTALLING…';try{const r=await fetch('/install?desktop='+document.getElementById('desktop').checked,{method:'POST'}),d=await r.json();if(d.error)throw Error(d.error);s.textContent=d.warning?'APP INSTALLED — '+d.warning+' (open EXE in install folder)':'INSTALLED SUCCESSFULLY — CLICK CLOSE SETUP';completed=true;b.textContent='INSTALL COMPLETE';}catch(e){s.textContent='ERROR: '+e.message;b.disabled=false;}}</script></body></html>`}
// The setup UI is a temporary local server, not a resident Windows service.
// It exits on Close Setup, browser pagehide, or loss of page heartbeats.
func main(){
 if len(os.Args)>1&&os.Args[1]=="--uninstall"{uninstall();return}
 mux:=http.NewServeMux()
 var lastBeat atomic.Int64
 lastBeat.Store(time.Now().UnixNano())
 quit:=make(chan struct{},1)
 requestQuit:=func(){select{case quit<-struct{}{}:default:}}
 mux.HandleFunc("/",func(w http.ResponseWriter,r *http.Request){
  lastBeat.Store(time.Now().UnixNano())
  w.Header().Set("Content-Type","text/html; charset=utf-8")
  _,_=w.Write([]byte(page()))
 })
 mux.HandleFunc("/brand.png",func(w http.ResponseWriter,r *http.Request){
  w.Header().Set("Content-Type","image/png")
  b,_:=payload.ReadFile("brand.png");_,_=w.Write(b)
 })
 mux.HandleFunc("/api/heartbeat",func(w http.ResponseWriter,r *http.Request){
  if r.Method!="POST"{http.Error(w,"Method not allowed",405);return}
  lastBeat.Store(time.Now().UnixNano());w.WriteHeader(204)
 })
 mux.HandleFunc("/api/quit",func(w http.ResponseWriter,r *http.Request){
  if r.Method!="POST"{http.Error(w,"Method not allowed",405);return}
  w.WriteHeader(204)
  if f,ok:=w.(http.Flusher);ok {f.Flush()}
  requestQuit()
 })
 mux.HandleFunc("/install",func(w http.ResponseWriter,r *http.Request){
  if r.Method!="POST"{http.Error(w,"Method not allowed",405);return}
  err:=install(r.URL.Query().Get("desktop")=="true")
  w.Header().Set("Content-Type","application/json")
  if err!=nil{_ =json.NewEncoder(w).Encode(map[string]string{"error":err.Error()})
  }else{_ =json.NewEncoder(w).Encode(map[string]string{"ok":"true","warning":installationWarnings})}
 })
 ln,err:=net.Listen("tcp","127.0.0.1:0");if err!=nil{panic(err)}
 server:=&http.Server{Handler:mux,ReadHeaderTimeout:5*time.Second}
 go func(){if err:=server.Serve(ln);err!=nil && err!=http.ErrServerClosed{requestQuit()}}()
 url:="http://"+ln.Addr().String()
 go func(){time.Sleep(500*time.Millisecond);if runtime.GOOS=="windows"{
  _=exec.Command("rundll32","url.dll,FileProtocolHandler",url).Start()
 }}()
 // Grace period for first browser launch. When a dashboard is open it pings every 1.5 seconds.
 go func(){
  timer:=time.NewTicker(2*time.Second);defer timer.Stop()
  grace:=time.Now().Add(20*time.Second)
  for range timer.C {
   if time.Now().Before(grace){continue}
   if time.Since(time.Unix(0,lastBeat.Load()))>8*time.Second{requestQuit();return}
  }
 }()
 <-quit
 ctx,cancel:=context.WithTimeout(context.Background(),2*time.Second);defer cancel()
 _=server.Shutdown(ctx)
}

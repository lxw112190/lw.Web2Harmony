#include <Windows.h>
#include <commctrl.h>
#include <commdlg.h>
#include <shobjidl.h>
#include <shellapi.h>
#include <wincodec.h>
#include <wrl/client.h>
#include "core/HarmonyProject.h"
#include "core/ProcessRunner.h"
#include "core/IconGenerator.h"
#include "core/Logging.h"
#include <map>
#include <memory>
#include <thread>
#include <vector>

using namespace lw::web2harmony;
namespace {
constexpr UINT Complete=WM_APP+1;
enum {Mode=101,Source,Name,Bundle,Version,Code,Icon,Output,AllowHttp,Fullscreen,Orientation,
      SelectSource=201,SelectIcon,ResetIcon,SelectOutput,
      Build=301,Status,Preview,SourceHint,ToolchainStatus,SigningStatus};
struct State {
    HWND window=nullptr; HFONT font=nullptr; HFONT titleFont=nullptr; HBITMAP bitmap=nullptr;
    bool busy=false; std::filesystem::path root;
};
struct Completion {bool success=false; std::wstring message; std::filesystem::path path;};
HWND Control(State& s,const wchar_t* cls,const wchar_t* text,DWORD style,int x,int y,int w,int h,int id=0) {
    const auto control=CreateWindowExW((style&ES_AUTOHSCROLL)?WS_EX_CLIENTEDGE:0,cls,text,
        WS_CHILD|WS_VISIBLE|style,x,y,w,h,s.window,reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)),nullptr,nullptr);
    SendMessageW(control,WM_SETFONT,reinterpret_cast<WPARAM>(s.font),TRUE);
    return control;
}
void Label(State& s,const wchar_t* text,int x,int y,int w=300) {Control(s,L"STATIC",text,0,x,y,w,22);}
void Edit(State& s,int id,const wchar_t* text,int x,int y,int w) {Control(s,L"EDIT",text,WS_TABSTOP|ES_AUTOHSCROLL,x,y,w,30,id);}
std::wstring Text(State& s,int id) {
    const auto child=GetDlgItem(s.window,id); std::vector<wchar_t> buffer(GetWindowTextLengthW(child)+1);
    GetWindowTextW(child,buffer.data(),static_cast<int>(buffer.size()));return buffer.data();
}
void Set(State& s,int id,const std::wstring& value) {SetWindowTextW(GetDlgItem(s.window,id),value.c_str());}
std::filesystem::path Select(HWND parent,bool directory) {
    IFileOpenDialog* dialog=nullptr;
    if(FAILED(CoCreateInstance(CLSID_FileOpenDialog,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&dialog)))) return {};
    DWORD flags=0;dialog->GetOptions(&flags);dialog->SetOptions(flags|FOS_FORCEFILESYSTEM|(directory?FOS_PICKFOLDERS:FOS_FILEMUSTEXIST));
    COMDLG_FILTERSPEC filter{L"PNG 图标",L"*.png"};
    if(!directory) dialog->SetFileTypes(1,&filter);
    std::filesystem::path selected;
    if(SUCCEEDED(dialog->Show(parent))) {
        IShellItem* item=nullptr;
        if(SUCCEEDED(dialog->GetResult(&item))) {
            PWSTR path=nullptr;if(SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH,&path))) {selected=path;CoTaskMemFree(path);}
            item->Release();
        }
    }
    dialog->Release();return selected;
}
void PreviewIcon(State& s,const std::filesystem::path& path) {
    using Microsoft::WRL::ComPtr;
    IconGenerator::Inspect(path);
    ComPtr<IWICImagingFactory> factory;
    ComPtr<IWICBitmapDecoder> decoder;
    ComPtr<IWICBitmapFrameDecode> frame;
    ComPtr<IWICBitmapScaler> scaler;
    ComPtr<IWICFormatConverter> converter;
    if(FAILED(CoCreateInstance(CLSID_WICImagingFactory,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&factory))) ||
       FAILED(factory->CreateDecoderFromFilename(path.c_str(),nullptr,GENERIC_READ,WICDecodeMetadataCacheOnLoad,&decoder)) ||
       FAILED(decoder->GetFrame(0,&frame)) || FAILED(factory->CreateBitmapScaler(&scaler)) ||
       FAILED(scaler->Initialize(frame.Get(),64,64,WICBitmapInterpolationModeFant)) ||
       FAILED(factory->CreateFormatConverter(&converter)) ||
       FAILED(converter->Initialize(scaler.Get(),GUID_WICPixelFormat32bppBGRA,WICBitmapDitherTypeNone,nullptr,0,WICBitmapPaletteTypeCustom)))
        throw std::runtime_error("Unable to preview PNG icon");
    BITMAPINFO info{};info.bmiHeader.biSize=sizeof(BITMAPINFOHEADER);info.bmiHeader.biWidth=64;
    info.bmiHeader.biHeight=-64;info.bmiHeader.biPlanes=1;info.bmiHeader.biBitCount=32;info.bmiHeader.biCompression=BI_RGB;
    void* pixels=nullptr;
    HBITMAP bitmap=CreateDIBSection(nullptr,&info,DIB_RGB_COLORS,&pixels,nullptr,0);
    if(!bitmap || FAILED(converter->CopyPixels(nullptr,64*4,64*64*4,static_cast<BYTE*>(pixels)))) {
        if(bitmap) DeleteObject(bitmap); throw std::runtime_error("Unable to draw icon");
    }
    SendMessageW(GetDlgItem(s.window,Preview),STM_SETIMAGE,IMAGE_BITMAP,reinterpret_cast<LPARAM>(bitmap));
    if(s.bitmap) DeleteObject(s.bitmap);s.bitmap=bitmap;
}
void RefreshStatus(State& s) {
    Set(s,ToolchainStatus,LocalToolchainReady(s.root)?L"工具链：已就绪":L"工具链：尚未配置，请先完成一次性配置");
    Set(s,SigningStatus,SigningConfigurationFor(s.root,WideToUtf8(Text(s,Bundle))).empty()?
        L"签名：未配置，将生成未签名 HAP，不能直接安装到真机":
        L"签名：已发现此应用的配置，将自动签名（需有效证书与设备 Profile）");
}
void SetBusy(State& s,bool busy) {
    s.busy=busy;
    for(const int id:{Mode,Source,Name,Bundle,Version,Code,Icon,Output,AllowHttp,Fullscreen,Orientation,
                     SelectSource,SelectIcon,ResetIcon,SelectOutput,Build})
        EnableWindow(GetDlgItem(s.window,id),!busy);
    if(!busy) EnableWindow(GetDlgItem(s.window,SelectSource),SendMessageW(GetDlgItem(s.window,Mode),CB_GETCURSEL,0,0)!=1);
}
void Start(State& s) {
    if(s.busy)return;
    try {
        HarmonyProject p;
        p.mode=SendMessageW(GetDlgItem(s.window,Mode),CB_GETCURSEL,0,0)==1?"remote":"local";
        p.source=Text(s,Source);p.url=WideToUtf8(Text(s,Source));p.name=WideToUtf8(Text(s,Name));
        p.bundleName=WideToUtf8(Text(s,Bundle));p.versionName=WideToUtf8(Text(s,Version));
        const auto code=Text(s,Code);
        if(code.empty() || code.find_first_not_of(L"0123456789")!=std::wstring::npos) throw std::runtime_error("Version Code must be a positive integer");
        const auto value=std::stoll(code);
        if(value<1 || value>2147483647)throw std::runtime_error("Version Code is out of range");
        p.versionCode=static_cast<int>(value);p.icon=Text(s,Icon);
        p.allowHttp=SendMessageW(GetDlgItem(s.window,AllowHttp),BM_GETCHECK,0,0)==BST_CHECKED;
        p.fullscreen=SendMessageW(GetDlgItem(s.window,Fullscreen),BM_GETCHECK,0,0)==BST_CHECKED;
        const auto orientation=SendMessageW(GetDlgItem(s.window,Orientation),CB_GETCURSEL,0,0);
        p.orientation=orientation==1?"portrait":orientation==2?"landscape":"auto";
        p.Validate();
        if(Text(s,Output).empty())throw std::runtime_error("Select a HAP output folder");
        const auto output=std::filesystem::absolute(Text(s,Output));const auto root=s.root;
        if(!LocalToolchainReady(root)) {
            MessageBoxW(s.window,L"请先完成一次性工具链配置，然后重新打开程序。详见 docs/LOCAL-BUILD.md。",L"工具链尚未就绪",MB_OK|MB_ICONINFORMATION);
            return;
        }
        SetBusy(s,true);
        Set(s,Status,L"正在打包鸿蒙 HAP，请稍候…");
        const auto window=s.window;
        std::thread([p,output,root,window]() {
            auto result=std::make_unique<Completion>();
            try {
                const auto artifact=PackageHap(p,output,root);
                result->success=true;result->path=artifact.parent_path();
                result->message=SigningConfigurationFor(root,p.bundleName).empty()?
                    L"未签名 HAP 已生成 · 仅用于构建验证，真机安装需要配置签名":L"已签名 HAP 已生成 · 请在 Profile 授权的设备上测试";
            } catch(const std::exception& error) {result->message=L"失败："+Utf8ToWide(error.what());PackerLogger().Error(error.what());}
            if(PostMessageW(window,Complete,0,reinterpret_cast<LPARAM>(result.get())))result.release();
        }).detach();
    } catch(const std::exception& error) {SetBusy(s,false);MessageBoxW(s.window,Utf8ToWide(error.what()).c_str(),L"请检查项目设置",MB_OK|MB_ICONERROR);}
}
void Interface(State& s) {
    const auto title=Control(s,L"STATIC",L"lw.Web2Harmony",0,30,20,500,40);
    SendMessageW(title,WM_SETFONT,reinterpret_cast<WPARAM>(s.titleFont),TRUE);
    Label(s,L"将 Web 项目快速打包为鸿蒙应用",32,65,600);Label(s,L"v" LW_VERSION,625,28,80);
    Control(s,L"BUTTON",L"01 网页来源",BS_GROUPBOX,25,105,680,175);
    Control(s,L"BUTTON",L"02 应用设置",BS_GROUPBOX,25,295,680,425);
    const auto mode=Control(s,L"COMBOBOX",L"",CBS_DROPDOWNLIST|WS_TABSTOP,45,145,225,120,Mode);
    SendMessageW(mode,CB_ADDSTRING,0,reinterpret_cast<LPARAM>(L"本地静态网页"));SendMessageW(mode,CB_ADDSTRING,0,reinterpret_cast<LPARAM>(L"在线网址"));SendMessageW(mode,CB_SETCURSEL,0,0);
    Control(s,L"BUTTON",L"允许 HTTP（仅建议可信内网）",BS_AUTOCHECKBOX|WS_TABSTOP,300,147,385,25,AllowHttp);
    Edit(s,Source,L"",45,195,530);Control(s,L"BUTTON",L"选择目录",WS_TABSTOP,585,195,100,30,SelectSource);
    Control(s,L"STATIC",L"选择 HTML / Vue / React 的静态构建目录（入口 index.html）",0,45,243,640,24,SourceHint);
    Label(s,L"应用名称",45,328,310);Edit(s,Name,L"我的鸿蒙应用",45,355,310);
    Label(s,L"Bundle Name",375,328,310);Edit(s,Bundle,L"com.example.myharmonyapp",375,355,310);
    Label(s,L"应用图标",45,402);
    Control(s,L"STATIC",L"",SS_BITMAP|SS_CENTERIMAGE,45,430,64,64,Preview);
    Edit(s,Icon,L"",125,430,450);Control(s,L"BUTTON",L"选择图标",WS_TABSTOP,585,428,100,30,SelectIcon);
    Control(s,L"BUTTON",L"使用默认",WS_TABSTOP,585,468,100,30,ResetIcon);
    Label(s,L"留空使用内置图标；建议 512×512 正方形 PNG",125,473,450);
    Label(s,L"Version Name",45,515,180);Label(s,L"Version Code",245,515,100);Label(s,L"屏幕方向",365,515,180);
    Edit(s,Version,L"1.0.0",45,540,180);Edit(s,Code,L"1",245,540,100);
    const auto direction=Control(s,L"COMBOBOX",L"",CBS_DROPDOWNLIST|WS_TABSTOP,365,540,180,140,Orientation);
    for(const auto text:{L"自动",L"竖屏",L"横屏"})SendMessageW(direction,CB_ADDSTRING,0,reinterpret_cast<LPARAM>(text));
    SendMessageW(direction,CB_SETCURSEL,0,0);
    Control(s,L"BUTTON",L"全屏显示",BS_AUTOCHECKBOX|WS_TABSTOP,565,542,120,25,Fullscreen);
    Label(s,L"HAP 输出目录",45,586);
    Edit(s,Output,(s.root/L"output").c_str(),45,611,530);Control(s,L"BUTTON",L"选择位置",WS_TABSTOP,585,611,100,30,SelectOutput);
    Control(s,L"STATIC",L"",0,45,656,640,22,ToolchainStatus);
    Control(s,L"STATIC",L"",0,45,686,640,22,SigningStatus);
    Control(s,L"BUTTON",L"生成鸿蒙 HAP",WS_TABSTOP|BS_DEFPUSHBUTTON,25,740,680,45,Build);
    Control(s,L"STATIC",L"准备就绪 · 请选择网页来源和 HAP 输出目录",0,25,804,680,36,Status);
    PreviewIcon(s,s.root/"assets/default-app-icon.png");
    RefreshStatus(s);
}
LRESULT CALLBACK WindowProc(HWND window,UINT message,WPARAM wp,LPARAM lp) {
    auto* s=reinterpret_cast<State*>(GetWindowLongPtrW(window,GWLP_USERDATA));
    try {
        if(message==WM_CREATE) {
            auto state=std::make_unique<State>();state->window=window;state->root=ApplicationRoot();
            state->font=CreateFontW(-16,0,0,0,FW_NORMAL,FALSE,FALSE,FALSE,DEFAULT_CHARSET,0,0,CLEARTYPE_QUALITY,0,L"Microsoft YaHei UI");
            state->titleFont=CreateFontW(-30,0,0,0,FW_SEMIBOLD,FALSE,FALSE,FALSE,DEFAULT_CHARSET,0,0,CLEARTYPE_QUALITY,0,L"Segoe UI");
            SetWindowLongPtrW(window,GWLP_USERDATA,reinterpret_cast<LONG_PTR>(state.get()));
            s=state.release();Interface(*s);return 0;
        }
        if(!s)return DefWindowProcW(window,message,wp,lp);
        if(message==WM_COMMAND && !s->busy) {
            const int id=LOWORD(wp);
            if(id==Build){Start(*s);return 0;}
            if(id==Mode && HIWORD(wp)==CBN_SELCHANGE) {
                const bool remote=SendMessageW(GetDlgItem(window,Mode),CB_GETCURSEL,0,0)==1;
                EnableWindow(GetDlgItem(window,SelectSource),!remote);
                Set(*s,Source,L"");
                Set(*s,SourceHint,remote?L"输入完整的 HTTPS 网址；HTTP 仅建议用于可信内网":L"选择 HTML / Vue / React 的静态构建目录（入口 index.html）");
                return 0;
            }
            if(id==Bundle && HIWORD(wp)==EN_CHANGE) {RefreshStatus(*s);return 0;}
            if(id==Icon && HIWORD(wp)==EN_KILLFOCUS) {
                PreviewIcon(*s,Text(*s,Icon).empty()?s->root/"assets/default-app-icon.png":std::filesystem::path(Text(*s,Icon)));
                return 0;
            }
            if(id==ResetIcon){Set(*s,Icon,L"");PreviewIcon(*s,s->root/"assets/default-app-icon.png");return 0;}
            const std::map<int,int> fields{{SelectSource,Source},{SelectIcon,Icon},{SelectOutput,Output}};
            const auto found=fields.find(id);
            if(found!=fields.end()) {
                const auto path=Select(window,id!=SelectIcon);
                if(!path.empty()) {if(id==SelectIcon)PreviewIcon(*s,path);Set(*s,found->second,path.wstring());}
                return 0;
            }
        }
        if(message==Complete) {
            std::unique_ptr<Completion> result(reinterpret_cast<Completion*>(lp));
            SetBusy(*s,false);RefreshStatus(*s);
            Set(*s,Status,result->message);
            if(result->success)ShellExecuteW(window,L"open",result->path.c_str(),nullptr,nullptr,SW_SHOWNORMAL);
            else MessageBoxW(window,(result->message+L"\n\n日志："+PackerLogFile().wstring()).c_str(),L"构建失败",MB_OK|MB_ICONERROR);
            return 0;
        }
        if(message==WM_CLOSE && s->busy) {MessageBoxW(window,L"正在构建，请等待完成后关闭。",L"lw.Web2Harmony",MB_OK);return 0;}
        if(message==WM_CTLCOLORSTATIC) {
            const auto dc=reinterpret_cast<HDC>(wp);SetBkColor(dc,GetSysColor(COLOR_WINDOW));SetBkMode(dc,OPAQUE);
            return reinterpret_cast<LRESULT>(GetSysColorBrush(COLOR_WINDOW));
        }
        if(message==WM_DESTROY) {
            if(s->bitmap)DeleteObject(s->bitmap);DeleteObject(s->font);DeleteObject(s->titleFont);delete s;
            SetWindowLongPtrW(window,GWLP_USERDATA,0);PostQuitMessage(0);return 0;
        }
    } catch(const std::exception& error) {
        PackerLogger().Error(error.what());MessageBoxW(window,Utf8ToWide(error.what()).c_str(),L"lw.Web2Harmony",MB_OK|MB_ICONERROR);
        if(message==WM_CREATE)return -1;
    }
    return DefWindowProcW(window,message,wp,lp);
}
}
int WINAPI wWinMain(HINSTANCE instance,HINSTANCE,PWSTR command,int) {
    SetProcessDPIAware();const auto com=CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);
    INITCOMMONCONTROLSEX common{sizeof(common),ICC_STANDARD_CLASSES};InitCommonControlsEx(&common);
    WNDCLASSEXW cls{sizeof(cls)};cls.hInstance=instance;cls.lpfnWndProc=WindowProc;cls.lpszClassName=L"lw.Web2Harmony";
    cls.hIcon=LoadIconW(instance,MAKEINTRESOURCEW(101));cls.hIconSm=cls.hIcon;cls.hCursor=LoadCursorW(nullptr,IDC_ARROW);
    cls.hbrBackground=reinterpret_cast<HBRUSH>(COLOR_WINDOW+1);
    RegisterClassExW(&cls);
    RECT bounds{0,0,730,850};const DWORD style=WS_OVERLAPPED|WS_CAPTION|WS_SYSMENU|WS_MINIMIZEBOX;
    AdjustWindowRectEx(&bounds,style,FALSE,WS_EX_CONTROLPARENT);
    RECT area{};SystemParametersInfoW(SPI_GETWORKAREA,0,&area,0);
    const auto window=CreateWindowExW(WS_EX_CONTROLPARENT,cls.lpszClassName,L"lw.Web2Harmony · 网页转鸿蒙应用",style,
        area.left+((area.right-area.left)-(bounds.right-bounds.left))/2,
        area.top+((area.bottom-area.top)-(bounds.bottom-bounds.top))/2,
        bounds.right-bounds.left,bounds.bottom-bounds.top,nullptr,nullptr,instance,nullptr);
    int result=1;
    if(window) {
        if(std::wstring(command)==L"--smoke-test"){
            wchar_t caption[128]{};GetWindowTextW(GetDlgItem(window,Build),caption,128);
            bool unexpected=false;
            EnumChildWindows(window,[](HWND child,LPARAM data)->BOOL {
                wchar_t text[128]{};GetWindowTextW(child,text,128);
                if(std::wstring(text).find(L"导出鸿蒙工程")!=std::wstring::npos ||
                   std::wstring(text).find(L"Java JDK 目录")!=std::wstring::npos ||
                   std::wstring(text).find(L"Command Line Tools 目录")!=std::wstring::npos)
                    *reinterpret_cast<bool*>(data)=true;
                return TRUE;
            },reinterpret_cast<LPARAM>(&unexpected));
            result=std::wstring(caption)==L"生成鸿蒙 HAP" && !unexpected &&
                (GetWindowLongW(window,GWL_STYLE)&(WS_MAXIMIZEBOX|WS_THICKFRAME))==0?0:1;
            DestroyWindow(window);
        }
        else {ShowWindow(window,SW_SHOW);MSG msg{};while(GetMessageW(&msg,nullptr,0,0)>0){if(!IsDialogMessageW(window,&msg)){TranslateMessage(&msg);DispatchMessageW(&msg);}}result=static_cast<int>(msg.wParam);}
    }
    if(SUCCEEDED(com))CoUninitialize();return result;
}

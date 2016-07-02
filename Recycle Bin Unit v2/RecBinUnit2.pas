unit RecBinUnit2 platform;

////////////////////////////////////////////////////////////////////////////////////
// RECYCLE-BIN-FUNCTIONS V2 BY DANIEL MARSCHALL                                   //
// E-MAIL: info@daniel-marschall.de                                               //
// WEB:    www.daniel-marschall.de                                                //
////////////////////////////////////////////////////////////////////////////////////
// Revision: 02 JUL 2016                                                          //
// This unit is freeware, but please link to my website if you are using it!      //
////////////////////////////////////////////////////////////////////////////////////
// Successfully tested with:                                                      //
// Windows 95b (without IE4 Shell Extensions)                                     //
// Windows 95b (with IE4 Shell Extensions)                                        //
// Windows 98-SE                                                                  //
// Windows NT4 SP6                                                                //
// Windows XP-SP3                                                                 //
// Windows 2000-SP4                                                               //
// Windows 2003 Server EE SP1                                                     //
// Windows Vista                                                                  //
// Windows 7                                                                      //
// Windows 10                                                                     //
////////////////////////////////////////////////////////////////////////////////////

// Delphi 7 Compatibility:  (TODO: compiler switches)
// - Remove "static"
// - Remove "strict"
// - Remove "$REGION"

// TODO: "blind reading" feature: read also INFO and INFO2 records mixed in one file (win2000 multiboot conflict)
// TODO: ReadBuffer �berall try-except
// TODO: Win7 : Drive GUIDs
// TODO: Win7 : Absolute vs. Relative size limitations
// TODO: Always check EOF before reading anything?
// TODO: Is it possible to identify a Vista-file that is not named $Ixxxxxx.ext?
// TODO: RecyclerGetInfofiles() check additionally for removable device?
//       RecyclerIsValid() is false.
// TODO: Make it possible to empty the recycle bin of one specific drive!
// TODO: Unknown! Do you know the answer?
//       - How does Windows 9x/NT manage the daylight saving time (if it does)?
//       - How does Windows Vista+ react to a RECYCLER\ folder on a NTFS device?
//       - How does Windows Vista+ react to a RECYCLED\ folder on a FAT device? ==> Win7: is ignored!
//       - How does Windows XP react to RECYCLED\ folder on a FAT device?
// TODO: Translate all comments from German to English
// TODO: do we need this (maybe not all drives have A: till Z:?) http://stackoverflow.com/questions/17110543/how-to-retrieve-the-disk-signature-of-all-the-disks-in-windows-using-delphi-7

// If enabled, the deletion timestamps will not be converted by the WinAPI.
{.$DEFINE FILETIME_DELPHI_CODE}

// If a value is set in HKEY_LOCAL_MACHINE, it will be prefered, even if gpedit.msc shows "Not configured"!
{$DEFINE GroupPolicyAcceptHKLMTrick}

interface

uses
  Windows, SysUtils, Classes, ContNrs, ShellAPI, Registry, Messages;

const
  RECBINUNIT_VERSION = '2016-07-02';

  RECYCLER_CLSID: TGUID = '{645FF040-5081-101B-9F08-00AA002F954E}';
  NULL_GUID: TGUID      = '{00000000-0000-0000-0000-000000000000}';

type
  EAPICallError = class(Exception);
  EEventCategoryNotDefined = class(Exception);
  EInvalidDrive = class(Exception);

  PSHQueryRBInfo = ^TSHQueryRBInfo;
  TSHQueryRBInfo = packed record
    cbSize      : dword;
    i64Size     : int64;
    i64NumItems : int64;
  end;

  TRbRecycleBinItem = class(TObject)
  strict private
    function GetSource: string;
  strict protected
    FSourceAnsi: AnsiString;
    FSourceUnicode: WideString;
    FID: string;
    FSourceDrive: Char;
    FDeletionTime: TDateTime;
    FOriginalSize: int64;
    FIndexFile: string;
    FRemovedEntry: boolean;
    procedure ReadFromStream(stream: TStream); virtual; abstract;
    function GetPhysicalFile: string; virtual; abstract; // protected, because it will be read by "property"
  public
    property PhysicalFile: string read GetPhysicalFile;
    property SourceAnsi: AnsiString read FSourceAnsi;
    property SourceUnicode: WideString read FSourceUnicode;
    property Source: string read GetSource; // will bei either ANSI or Unicode, sepending on the Delphi version
    property ID: string read FID;
    property SourceDrive: Char read FSourceDrive;
    property DeletionTime: TDateTime read FDeletionTime;
    property OriginalSize: int64 read FOriginalSize;
    property IndexFile: string read FIndexFile;
    property RemovedEntry: boolean read FRemovedEntry; // the file is NOT in the recycle bin anymore!

    // Attention: There are not an official API calls. The delete and recover
    // functions might fail and/or damage the shell cache. Handle with care!
    function DeleteFile: boolean; virtual; abstract;
    function RecoverFile: boolean; virtual; abstract;
    function OpenFile: boolean; virtual; abstract;
  end;

  TRbInfo1Item = class(TRbRecycleBinItem)
  strict protected
    procedure ReadFromStream(stream: TStream); override;
    function GetPhysicalFile: string; override;
  public
    constructor Create(fs: TStream; AIndexFile: string);
    function DeleteFile: boolean; override;
    // TODO: function RecoverFile: boolean; override;
    // TODO: function OpenFile: boolean; override;
  end;

  TRbInfo2Item = class(TRbRecycleBinItem)
  strict protected
    procedure ReadFromStream(stream: TStream); override;
    function GetPhysicalFile: string; override;
  public
    constructor Create(fs: TStream; AIndexFile: string);
    function DeleteFile: boolean; override;
    // TODO: function RecoverFile: boolean; override;
    // TODO: function OpenFile: boolean; override;
  end;

  TRbVistaItem = class(TRbRecycleBinItem)
  strict protected
    procedure ReadFromStream(stream: TStream); override;
    function GetPhysicalFile: string; override;
  public
    constructor Create(fs: TStream; AIndexFile, AID: string);
    function DeleteFile: boolean; override;
    // TODO: function RecoverFile: boolean; override;
    // TODO: function OpenFile: boolean; override;
  end;

  TRbRecycleBin = class(TObject)
  strict private
    FFileOrDirectory: string;
    FSID: string;
  public
    constructor Create(AFileOrDirectory: string; ASID: string='');

    function GetItem(id: string): TRbRecycleBinItem;
    procedure ListItems(list: TObjectList{TRbRecycleBinItem});
    function CheckIndexes(slErrors: TStrings): boolean;

    property FileOrDirectory: string read FFileOrDirectory;
    property SID: string read FSID;
  end;

  // TODO: Wie sieht es aus mit Laufwerken, die nur als Mount-Point eingebunden sind?
  TRbDrive = class(TObject)
  strict private
    FDriveLetter: Char;

    // will return NULL_GUID in case of an error or if it is not supported
    function GetVolumeGUID: TGUID;
  strict protected
    function IsFAT: boolean;
    procedure CheckDriveExisting;
  public
    constructor Create(ADriveLetter: Char);

    // Wenn UserSID='', dann werden alle Recycler gefunden
    procedure ListRecycleBins(list: TObjectList{TRbRecycleBin}; UserSID: string='');

    property DriveLetter: Char read FDriveLetter;
    property VolumeGUID: TGUID read GetVolumeGUID;
    function GetAPIInfo: TSHQueryRBInfo;
    function GetSize: int64;
    function GetNumItems: int64;
    function IsEmpty: boolean;

    function GetMaxPercentUsage: integer;
    function GetNukeOnDelete: boolean;

    // These functions will check the global configuration and group policy, too.
    function RecyclerGetPercentUsageAutoDeterminate: integer;
    function RecyclerIsNukeOnDeleteAutoDeterminate: boolean;
  end;

  GPOLICYBOOL = (gpUndefined, gpEnabled, gpDisabled);

  TRecycleBinManager = class(TObject)
  public
    class procedure ListDrives(list: TObjectList{TRbDrive}); static;
    class function RecycleBinPossible(Drive: Char): boolean; static;

    class function OwnRecyclersSize: int64; static;
    class function OwnRecyclersNumItems: int64; static;
    class function OwnRecyclersEmpty: boolean; static;

    class function EmptyOwnRecyclers(flags: cardinal): boolean; overload; static;
    class function EmptyOwnRecyclers(sound, progress, confirmation: boolean): boolean; overload; static;

    class function RecyclerGetCurrentIconString: string; static;
    class function RecyclerGetDefaultIconString: string; static;
    class function RecyclerGetEmptyIconString: string; static;
    class function RecyclerGetFullIconString: string; static;

    class function GetGlobalMaxPercentUsage: integer; static; // TODO: In Win Vista: absolute and not relative sizes
    class function GetGlobalNukeOnDelete: boolean; static;
    class function UsesGlobalSettings: boolean; static;

    class function RecyclerGetName: string; static;
    class function RecyclerGetInfoTip: string; static;
    class function RecyclerGetIntroText: string; static;

    class function RecyclerEmptyEventGetCurrentSound: string; static;
    class function RecyclerEmptyEventGetDefaultSound: string; static;
    class function RecyclerEmptyEventGetName: string; static;
    class function RecyclerEmptyEventGetSound(ACategory: string): string; static;
    class procedure RecyclerEmptyEventGetSoundCategories(AStringList: TStringList); static;

    // TODO: In future also detect for other users
    // TODO: Also make a setter (incl. Message to Windows Explorer?)
    class function RecyclerGroupPolicyConfirmFileDelete: GPOLICYBOOL; static;
    class function RecyclerGroupPolicyNoRecycleFiles: GPOLICYBOOL; static;
    class function RecyclerGroupPolicyRecycleBinSize: integer; static;

    class function RecyclerConfirmationDialogEnabled: boolean; static;
    class procedure RecyclerConfirmationDialogSetEnabled(NewSetting: boolean); static;
    class function RecyclerShellStateConfirmationDialogEnabled: boolean; static;

    // Diese Funktion ist false, wenn sie z.B. unter Windows 95 ohne Internet Explorer
    // 4.0 Shell Extension ausgef�hrt wird. Wenn abw�rtskompatibler Code geschrieben
    // werden soll, sollte RecyclerQueryFunctionAvailable() verwendet werden, da
    // unter Windows 95 folgende Funktionalit�ten NICHT vorhanden sind:
    // - RecyclerIsEmpty
    // - RecyclerGetNumItems
    // - RecyclerGetSize
    // - RecyclerGetAPIInfo
    class function RecyclerQueryFunctionAvailable: boolean; static;

    class function RecyclerAddFileOrFolder(FileOrFolder: string; confirmation: boolean=false): boolean; static;
  end;

function GPBoolToString(value: GPOLICYBOOL): string;

implementation

uses
  RecBinUnitLowLvl;

{$REGION 'WinAPI/RTL declarations'}
(*
const
  {$IFDEF MSWINDOWS}
    shell32  = 'shell32.dll';
    advapi32 = 'advapi32.dll';
    kernel32 = 'kernel32.dll';
  {$ENDIF}
  {$IFDEF LINUX}
    shell32  = 'libshell32.borland.so';
    advapi32 = 'libwine.borland.so';
    kernel32 = 'libwine.borland.so';
  {$ENDIF}
*)

type
  SHELLSTATE = record
    Flags1: DWORD;
(*
    BOOL fShowAllObjects : 1;
    BOOL fShowExtensions : 1;
    BOOL fNoConfirmRecycle : 1;

    BOOL fShowSysFiles : 1;
    BOOL fShowCompColor : 1;
    BOOL fDoubleClickInWebView : 1;
    BOOL fDesktopHTML : 1;
    BOOL fWin95Classic : 1;
    BOOL fDontPrettyPath : 1;
    BOOL fShowAttribCol : 1; // No longer used, dead bit
    BOOL fMapNetDrvBtn : 1;
    BOOL fShowInfoTip : 1;
    BOOL fHideIcons : 1;
    BOOL fWebView : 1;
    BOOL fFilter : 1;
    BOOL fShowSuperHidden : 1;
    BOOL fNoNetCrawling : 1;
*)
    dwWin95Unused: DWORD; // Win95 only - no longer supported pszHiddenFileExts
    uWin95Unused: UINT; // Win95 only - no longer supported cbHiddenFileExts

    // Note: Not a typo!  This is a persisted structure so we cannot use LPARAM
    lParamSort: Integer;
    iSortDirection: Integer;

    version: UINT;

    // new for win2k. need notUsed var to calc the right size of ie4 struct
    // FIELD_OFFSET does not work on bit fields
    uNotUsed: UINT; // feel free to rename and use
    Flags2: DWORD;
(*
    BOOL fSepProcess: 1;
    // new for Whistler.
    BOOL fStartPanelOn: 1;       //Indicates if the Whistler StartPanel mode is ON or OFF.
    BOOL fShowStartPage: 1;      //Indicates if the Whistler StartPage on desktop is ON or OFF.
    UINT fSpareFlags : 13;
*)
  end;
  LPSHELLSTATE = ^SHELLSTATE;

const
  // Masks for the SHELLSTATE
  SSF_SHOWALLOBJECTS       = $00000001;
  SSF_SHOWEXTENSIONS       = $00000002;
  SSF_HIDDENFILEEXTS       = $00000004;
  SSF_SERVERADMINUI        = $00000004;
  SSF_SHOWCOMPCOLOR        = $00000008;
  SSF_SORTCOLUMNS          = $00000010;
  SSF_SHOWSYSFILES         = $00000020;
  SSF_DOUBLECLICKINWEBVIEW = $00000080;
  SSF_SHOWATTRIBCOL        = $00000100;
  SSF_DESKTOPHTML          = $00000200;
  SSF_WIN95CLASSIC         = $00000400;
  SSF_DONTPRETTYPATH       = $00000800;
  SSF_SHOWINFOTIP          = $00002000;
  SSF_MAPNETDRVBUTTON      = $00001000;
  SSF_NOCONFIRMRECYCLE     = $00008000;
  SSF_HIDEICONS            = $00004000;
  SSF_FILTER               = $00010000;
  SSF_WEBVIEW              = $00020000;
  SSF_SHOWSUPERHIDDEN      = $00040000;
  SSF_SEPPROCESS           = $00080000;
  SSF_NONETCRAWLING        = $00100000;
  SSF_STARTPANELON         = $00200000;
  SSF_SHOWSTARTPAGE        = $00400000;
{$ENDREGION}

resourcestring
  LNG_API_CALL_ERROR = 'Error while calling the API. Additional information: "%s".';
  LNG_NOT_CALLABLE = '%s not callable';
  LNG_ERROR_CODE = '%s (Arguments: %s) returns error code %s';
  LNG_FILE_NOT_FOUND = 'File not found: %s';
  LNG_INVALID_INFO_FORMAT = 'Is not INFO or INFO2: %s';
  LNG_DRIVE_NOT_EXISTING = 'Drive %s does not exist.';

const
  C_SHQueryRecycleBin = 'SHQueryRecycleBinA';
  C_GetVolumeNameForVolumeMountPoint = 'GetVolumeNameForVolumeMountPointA';
  C_SHEmptyRecycleBinA = 'SHEmptyRecycleBinA';
  C_SHGetSettings = 'SHGetSettings';
  C_SHGetSetSettings = 'SHGetSetSettings';

type
  TSHQueryRecycleBin = function(pszRootPath: LPCTSTR; var pSHQueryRBInfo: TSHQueryRBInfo): HRESULT; stdcall;
  TGetVolumeNameForVolumeMountPoint = function(lpszVolumeMountPoint: LPCTSTR; lpszVolumeName: LPTSTR; cchBufferLength: DWORD): BOOL; stdcall;
  TSHEmptyRecycleBin = function(Wnd: HWND; pszRootPath: PChar; dwFlags: DWORD): HRESULT; stdcall;
  TSHGetSettings = procedure(var lpss: SHELLSTATE; dwMask: DWORD) stdcall;
  TSHGetSetSettings = procedure(var lpss: SHELLSTATE; dwMask: DWORD; bSet: BOOL) stdcall;

function GetDriveGUID(driveLetter: Char; var guid: TGUID): DWORD;
var
  Buffer: array[0..50] of AnsiChar;
  x: string;
  PGetVolumeNameForVolumeMountPoint: TGetVolumeNameForVolumeMountPoint;
  RBHandle: THandle;
begin
  RBHandle := LoadLibrary(kernel32);
  try
    if RBHandle <> 0 then
    begin
      PGetVolumeNameForVolumeMountPoint := GetProcAddress(RBHandle, C_GetVolumeNameForVolumeMountPoint);
      if not Assigned(@PGetVolumeNameForVolumeMountPoint) then
      begin
        result := GetLastError;
        FreeLibrary(RBHandle);
        RBHandle := 0;
      end
      else
      begin
        if PGetVolumeNameForVolumeMountPoint(PAnsiChar(driveLetter+':\'), Buffer, SizeOf(Buffer)) then
        begin
          x := buffer;
          x := copy(x, 11, 38);
          guid := StringToGUID(x);
          result := ERROR_SUCCESS;
        end
        else
          result := GetLastError;
      end;
    end
    else result := GetLastError;
  finally
    if RBHandle <> 0 then FreeLibrary(RBHandle);
  end;
end;

function FileTimeToDateTime(FileTime: FILETIME): TDateTime;
{$IFDEF FILETIME_DELPHI_CODE}
var
  SystemTime: TSystemTime;
  nowUTC: TDateTime;
  gmtDifference: int64;
begin
  GetSystemTime(SystemTime);
  with SystemTime do
  begin
    // http://www.delphipraxis.net/post340194.html#34019
    nowUTC := EncodeDate(wYear, wMonth, wDay) +
              EncodeTime(wHour, wMinute, wSecond, wMilliseconds);
  end;

  gmtDifference := datetimetounix(nowUTC) - datetimetounix(Now);

  // http://www.e-fense.com/helix/Docs/Recycler_Bin_Record_Reconstruction.pdf states:
  // UnixTime = 0.0000001 * NTTime + 11644473600
  // This is wrong! The correct formula is:
  // UnixTime = 0.0000001 * NTTime - 11644473600 + c * 3600
  // c = GMT-Difference (MEZ = 1) inclusive daylight saving time (+3600 seconds)
  result := unixtodatetime(round(0.0000001 * int64(FileTime)) - 11644473600 - gmtDifference);
{$ELSE}
var
  LocalTime: TFileTime;
  DOSTime: Integer;
begin
  FileTimeToLocalFileTime(FileTime, LocalTime);
  FileTimeToDosDateTime(LocalTime, LongRec(DOSTime).Hi, LongRec(DOSTime).Lo);
  Result := FileDateToDateTime(DOSTime);
{$ENDIF}
end;

function DeleteDirectory(const Name: string): boolean;
var
  F: TSearchRec;
begin
  result := true;
  if FindFirst(IncludeTrailingPathDelimiter(Name) + '*', faAnyFile, F) = 0 then
  begin
    try
      repeat
        if F.Attr and faDirectory <> 0 then
        begin
          if (F.Name <> '.') and (F.Name <> '..') then
          begin
            result := result and DeleteDirectory(IncludeTrailingPathDelimiter(Name) + F.Name);
          end;
        end
        else
        begin
          if not DeleteFile(IncludeTrailingPathDelimiter(Name) + F.Name) then result := false;
        end;
      until FindNext(F) <> 0;
    finally
      FindClose(F);
    end;
    if not RemoveDir(Name) then result := false;
  end;
end;

function DriveLetterToDriveNumber(driveLetter: Char): integer;
var
  tmp: string;
begin
  tmp := LowerCase(driveLetter);
  result := Ord(tmp[1])-Ord('a');
end;

function GetStringFromDLL(filename: string; num: integer): string;
const
  // Source: http://www.eggheadcafe.com/forumarchives/vcmfc/sep2005/post23917443.asp
  MAX_BUF = 4097; // OK?
var
  hLib: THandle;
  buf: array[0..MAX_BUF] of char;
begin
  hLib := LoadLibrary(PChar(filename));
  try
    LoadString(hLib, num, buf, sizeof(buf));
    result := buf;
  finally
    FreeLibrary(hLib);
  end;
end;

function ExpandEnvStr(const szInput: string): string;
const
  MAXSIZE = 32768; // laut PSDK sind 32k das Maximum
begin
  // Source: http://www.delphi-library.de/topic_Umgebungsvariable+in+einem+String+aufloesen_20516,0.html
  SetLength(Result,MAXSIZE);
  SetLength(Result,ExpandEnvironmentStrings(pchar(szInput),
    @Result[1],length(Result))-1); //-1 um abschlie�endes #0 zu verwerfen
end;

function DecodeReferenceString(s: string): string;
var
  dll, id, lang, cache: string;
  sl, sl2: tstringlist;
begin
  // Beispiele
  // Papierkorb                                                 -- Windows 95
  // @C:\WINNT\system32\shell32.dll,-8964@1031,Papierkorb       -- Windows 2000

  if Copy(s, 1, 1) = '@' then
  begin
    // Referenz auf eine DLL
    // @<dll>,-<id>[@<lang>][,<cache>]

    sl := TStringList.Create;
    try
      // '@' am Anfang entfernen
      s := Copy(s, 2, length(s)-1);

      // Nach ',' auftrennen
      // sl[0] --> dll
      // sl[1] --> -id@lang
      // sl[2] --> cache
      sl.CommaText := s;

      if sl.Count > 2 then
      begin
        // Das Ergebnis ist bereits im Klartext vorhanden und muss nicht extrahiert werden
        // Ist bei Windows 2000 der Fall
        cache := sl[2];
        result := cache;
        exit;
      end;

      if sl.Count > 1 then
      begin
        dll := sl[0];

        sl2 := TStringList.Create;
        try
          // Nach '@' auftrennen
          // sl2[0] --> id
          // sl2[1] --> lang
          sl2.CommaText := StringReplace(sl[1], '@', ',', [rfReplaceAll]);

          id := sl2[0];

          if sl2.Count > 1 then
          begin
            // ToDo: In Zukunft beachten, sofern m�glich
            lang := sl2[1];
          end;

          // Umgebungsvariablen erkennen und Minuszeichen entfernen
          result := GetStringFromDLL(ExpandEnvStr(dll), -StrToInt(id));
        finally
          sl2.Free;
        end;
      end
      else
      begin
        // Zu wenige Informationen!

        result := '';
      end;
    finally
      sl.Free;
    end;
  end
  else
  begin
    // Kein Hinweis auf eine Referenz
    result := s;
  end;
end;

function GPBoolToString(value: GPOLICYBOOL): string;
begin
  case value of
    gpUndefined: result := 'Not configured';
    gpEnabled: result := 'Enabled';
    gpDisabled: result := 'Disabled';
  end;
end;

{ TRbRecycleBin }

constructor TRbRecycleBin.Create(AFileOrDirectory: string; ASID: string='');
begin
  inherited Create;

  FFileOrDirectory := AFileOrDirectory;
  FSID := ASID;
end;

// TODO: also a function that tests if the data files are still existing
function TRbRecycleBin.CheckIndexes(slErrors: TStrings): boolean;

  procedure _Assert(assertion: boolean; msg: string; args: array of const);
  begin
    if not assertion then
    begin
      slErrors.Add(Format(msg, args));
      result := false;
    end;
  end;

  procedure _HandleIndexFile(AFile: string);
  var
    fs: TFileStream;
    infoHdr: TRbInfo12Header;
  resourcestring
    LNG_IDXERR_VISTA_FILESIZE = '%s: Vista index file has wrong size';
    LNG_IDXERR_INFO_RECSIZE_UNEXPECTED = '%s: record size unexpected';
    LNG_IDXERR_INFO_UNEXPECTED_EOF = '%s: file size wrong';
  begin
    fs := TFileStream.Create(AFile, fmOpenRead);
    try
      fs.Seek(0, soFromBeginning);

      // TODO: LNG_*

      if SameText(copy(ExtractFileName(AFile), 1, 2), '$I') then
      begin
        _Assert(fs.Size = SizeOf(TRbVistaItem), LNG_IDXERR_VISTA_FILESIZE, [AFile]);
      end
      else if SameText(ExtractFileName(AFile), 'INFO') then
      begin
        fs.ReadBuffer(infoHdr, SizeOf(infoHdr));
        _Assert(infoHdr.recordLength = SizeOf(TRbInfoRecord), LNG_IDXERR_INFO_RECSIZE_UNEXPECTED, [AFile]);
        _Assert((fs.Size-fs.Position) mod infoHdr.recordLength = 0, LNG_IDXERR_INFO_UNEXPECTED_EOF, [AFile]);
        // TODO: we can also check infoHdr.totalSize
      end
      else if SameText(ExtractFileName(AFile), 'INFO2') then
      begin
        fs.ReadBuffer(infoHdr, SizeOf(infoHdr));
        _Assert(infoHdr.recordLength = SizeOf(TRbInfo2Record), LNG_IDXERR_INFO_RECSIZE_UNEXPECTED, [AFile]);
        _Assert((fs.Size-fs.Position) mod infoHdr.recordLength = 0, LNG_IDXERR_INFO_UNEXPECTED_EOF, [AFile]);
      end;

      // TODO: we could check each item for invalid stuff...?
    finally
      FreeAndNil(fs);
    end;
  end;

  procedure _HandleVistaDir(ADirectory: string);
  var
    SR: TSearchRec;
  begin
    ADirectory := IncludeTrailingPathDelimiter(ADirectory);

    if FindFirst(ADirectory + '$I*', faAnyFile, SR) = 0 then
    begin
      repeat
        _HandleIndexFile(ADirectory+sr.Name);
      until FindNext(SR) <> 0;
    end;
    FindClose(SR);
  end;

begin
  result := true;

  if DirectoryExists(FFileOrDirectory) then // Vista, as well as directories with INFO and INFO2
  begin
    _HandleVistaDir(FFileOrDirectory);

    if FileExists(IncludeTrailingPathDelimiter(FFileOrDirectory) + 'INFO2') then
    begin
      _HandleIndexFile(IncludeTrailingPathDelimiter(FFileOrDirectory) + 'INFO2');
    end;

    if FileExists(IncludeTrailingPathDelimiter(FFileOrDirectory) + 'INFO') then
    begin
      _HandleIndexFile(IncludeTrailingPathDelimiter(FFileOrDirectory) + 'INFO');
    end;
  end
  else if FileExists(FFileOrDirectory) then
  begin
    _HandleIndexFile(FFileOrDirectory);
  end
  else raise Exception.CreateFmt(LNG_FILE_NOT_FOUND, [FFileOrDirectory]);
end;

function TRbRecycleBin.GetItem(id: string): TRbRecycleBinItem;

  procedure _HandleIndexFile(AFile: string);
  var
    fs: TFileStream;
    infoHdr: TRbInfo12Header;
    testItem: TRbRecycleBinItem;
  begin
    fs := TFileStream.Create(AFile, fmOpenRead);
    try
      fs.Seek(0, soFromBeginning);

      if fs.Size = SizeOf(TRbVistaRecord) then
      begin
        if SameText(ExtractFileName(AFile), '$I'+id) then
        begin
          result := TRbVistaItem.Create(fs, AFile, id);
        end;
      end
      else
      begin
        fs.ReadBuffer(infoHdr, SizeOf(infoHdr));
        case infoHdr.recordLength of
          SizeOf(TRbInfoRecord):
          begin
            while fs.Position < fs.size do
            begin
              testItem := TRbInfo1Item.Create(fs, AFile);
              if testItem.ID = id then
              begin
                result := testItem;
                break;
              end;
            end;
          end;
          SizeOf(TRbInfo2Record):
          begin
            while fs.Position < fs.size do
            begin
              testItem := TRbInfo2Item.Create(fs, AFile);
              if testItem.ID = id then
              begin
                result := testItem;
                break;
              end;
            end;
          end
          else
          begin
            raise Exception.CreateFmt(LNG_INVALID_INFO_FORMAT, [AFile]);
          end;
        end;
      end;
    finally
      FreeAndNil(fs);
    end;
  end;

  procedure _HandleVistaDir(ADirectory: string);
  var
    SR: TSearchRec;
    fs: TFileStream;
    id: string;
  begin
    ADirectory := IncludeTrailingPathDelimiter(ADirectory);

    if FileExists(ADirectory + '$I' + id) then
    begin
      fs := TFileStream.Create(ADirectory+sr.Name, fmOpenRead);
      try
        fs.Seek(0, soFromBeginning);
        result := TRbVistaItem.Create(fs, ADirectory+sr.Name, id);
      finally
        FreeAndNil(fs);
      end;
    end;
  end;

begin
  result := nil;

  if DirectoryExists(FFileOrDirectory) then // Vista, as well as directories with INFO and INFO2
  begin
    _HandleVistaDir(FFileOrDirectory);
    if Assigned(result) then exit;

    if FileExists(IncludeTrailingPathDelimiter(FFileOrDirectory) + 'INFO2') then
    begin
      _HandleIndexFile(IncludeTrailingPathDelimiter(FFileOrDirectory) + 'INFO2');
      if Assigned(result) then exit;
    end;

    if FileExists(IncludeTrailingPathDelimiter(FFileOrDirectory) + 'INFO') then
    begin
      _HandleIndexFile(IncludeTrailingPathDelimiter(FFileOrDirectory) + 'INFO');
      if Assigned(result) then exit;
    end;
  end
  else if FileExists(FFileOrDirectory) then
  begin
    _HandleIndexFile(FFileOrDirectory);
    if Assigned(result) then exit;
  end
  else raise Exception.CreateFmt(LNG_FILE_NOT_FOUND, [FFileOrDirectory]);
end;

procedure TRbRecycleBin.ListItems(list: TObjectList{TRbRecycleBinItem});

  procedure _HandleIndexFile(AFile: string);
  var
    fs: TFileStream;
    infoHdr: TRbInfo12Header;
    testID: string;
  begin
    fs := TFileStream.Create(AFile, fmOpenRead);
    try
      fs.Seek(0, soFromBeginning);

      if fs.Size = SizeOf(TRbVistaRecord) then
      begin
        testID := ExtractFileName(AFile);
        if SameText(copy(testID, 1, 2), '$I') then
          testID := copy(testID, 3, Length(testID)-2)
        else
          testID := '';

        list.Add(TRbVistaItem.Create(fs, AFile, testID));
      end
      else
      begin
        fs.ReadBuffer(infoHdr, SizeOf(infoHdr));
        case infoHdr.recordLength of
          SizeOf(TRbInfoRecord):
          begin
            while fs.Position < fs.size do
            begin
              list.Add(TRbInfo1Item.Create(fs, AFile));
            end;
          end;
          SizeOf(TRbInfo2Record):
          begin
            while fs.Position < fs.size do
            begin
              list.Add(TRbInfo2Item.Create(fs, AFile));
            end;
          end
          else
          begin
            raise Exception.CreateFmt(LNG_INVALID_INFO_FORMAT, [AFile]);
          end;
        end;
      end;
    finally
      FreeAndNil(fs);
    end;
  end;

  procedure _HandleVistaDir(ADirectory: string);
  var
    SR: TSearchRec;
    fs: TFileStream;
    id: string;
  begin
    ADirectory := IncludeTrailingPathDelimiter(ADirectory);

    if FindFirst(ADirectory + '$I*', faAnyFile, SR) = 0 then
    begin
      repeat
        id := sr.Name;
        { id := ChangeFileExt(id, ''); }  // Removed code: We keep the file extention as part of the ID, because we do not know if the ID is otherwise unique
        id := Copy(id, 3, Length(id)-2);

        fs := TFileStream.Create(ADirectory+sr.Name, fmOpenRead);
        try
          fs.Seek(0, soFromBeginning);
          list.Add(TRbVistaItem.Create(fs, ADirectory+sr.Name, id));
        finally
          FreeAndNil(fs);
        end;
      until FindNext(SR) <> 0;
    end;
    FindClose(SR);
  end;

begin
  if DirectoryExists(FFileOrDirectory) then // Vista, as well as directories with INFO and INFO2
  begin
    _HandleVistaDir(FFileOrDirectory);

    if FileExists(IncludeTrailingPathDelimiter(FFileOrDirectory) + 'INFO2') then
    begin
      _HandleIndexFile(IncludeTrailingPathDelimiter(FFileOrDirectory) + 'INFO2');
    end;

    if FileExists(IncludeTrailingPathDelimiter(FFileOrDirectory) + 'INFO') then
    begin
      _HandleIndexFile(IncludeTrailingPathDelimiter(FFileOrDirectory) + 'INFO');
    end;
  end
  else if FileExists(FFileOrDirectory) then
  begin
    _HandleIndexFile(FFileOrDirectory);
  end
  else raise Exception.CreateFmt(LNG_FILE_NOT_FOUND, [FFileOrDirectory]);
end;

{ TRbDrive }

procedure TRbDrive.CheckDriveExisting;
begin
  // Does the drive exist?
  // see http://www.delphipraxis.net/post2933.html
  if not GetLogicalDrives and (1 shl DriveLetterToDriveNumber(FDriveLetter)) <> 0 then
  begin
    raise EInvalidDrive.CreateFmt(LNG_DRIVE_NOT_EXISTING, [UpperCase(FDriveLetter)+':']);
  end;
end;

constructor TRbDrive.Create(ADriveLetter: Char);
begin
  inherited Create;

  FDriveLetter := ADriveLetter;
  CheckDriveExisting;
end;

function TRbDrive.GetAPIInfo: TSHQueryRBInfo;
var
  PSHQueryRecycleBin: TSHQueryRecycleBin;
  RBHandle: THandle;
  res: HRESULT;
  Path: string;
begin
  Path := FDriveLetter + ':\';

  // Ref: http://www.delphipraxis.net/post1291.html

  RBHandle := LoadLibrary(shell32);
  try
    PSHQueryRecycleBin := nil;
    if RBHandle <> 0 then
    begin
      PSHQueryRecycleBin := GetProcAddress(RBHandle, C_SHQueryRecycleBin);
      if not Assigned(@PSHQueryRecycleBin) then
      begin
        FreeLibrary(RBHandle);
        RBHandle := 0;
      end;
    end;

    FillChar(result, SizeOf(TSHQueryRBInfo), 0);
    result.cbSize := SizeOf(TSHQueryRBInfo);

    if (RBHandle <> 0) and Assigned(PSHQueryRecycleBin) then
    begin
      res := PSHQueryRecycleBin(PChar(Path), result);
      // if Succeeded(res) then
      if res = S_OK then
      begin
        // Alles OK, unser result hat nun die gew�nschten Daten.
      end
      else
      begin
        // Since Windows Vista, SHQueryRecycleBin will fail with E_FAIL (80004005)
        // if Path is a floppy or CD drive...
        raise EAPICallError.CreateFmt(LNG_API_CALL_ERROR, [Format(LNG_ERROR_CODE, [C_SHQueryRecycleBin, Path, '0x'+IntToHex(res, 2*SizeOf(HRESULT))])]);
      end;
    end
    else
      raise EAPICallError.CreateFmt(LNG_API_CALL_ERROR, [Format(LNG_NOT_CALLABLE, [C_SHQueryRecycleBin])]);
  finally
    if RBHandle <> 0 then FreeLibrary(RBHandle);
  end;
end;

function TRbDrive.GetMaxPercentUsage: integer;
var
  reg: TRegistry;
  purgeInfo: TRbWin95PurgeInfo;
const
  RES_DEFAULT = 10; // Windows 95 - Standardwert
begin
  result := RES_DEFAULT;

  reg := TRegistry.Create;
  try
    reg.RootKey := HKEY_LOCAL_MACHINE;

    // Im Auslieferungszustand von Windows 95 ist dieser Schl�ssel nicht vorhanden.
    // Er wird bei der ersten �nderung der Papierkorb-Einstellungen erstellt.
    if reg.OpenKeyReadOnly('SOFTWARE\Microsoft\Windows\CurrentVersion\explorer\BitBucket') then
    begin
      if reg.OpenKeyReadOnly(FDriveLetter) then
      begin
        if reg.ValueExists('Percent') then
        begin
          // Windows 2000 - Informationen liegen aufgeschl�sselt in der Registry

          result := reg.ReadInteger('Percent');
        end;
      end
      else
      begin
        if reg.ValueExists('PurgeInfo') then
        begin
          // Windows 95 - Kodierte Informationen liegen in PurgeInfo

          reg.ReadBinaryData('PurgeInfo', purgeInfo, SizeOf(purgeInfo));

          result := purgeInfo.percentDrive[FDriveLetter];
        end;
      end;

      reg.CloseKey;
    end;
  finally
    reg.Free;
  end;
end;

function TRbDrive.RecyclerGetPercentUsageAutoDeterminate: integer;
var
  gpSetting: integer;
begin
  gpSetting := TRecycleBinManager.RecyclerGroupPolicyRecycleBinSize;
  if gpSetting <> -1 then
    result := gpSetting
  else if TRecycleBinManager.UsesGlobalSettings then
    result := TRecycleBinManager.GetGlobalMaxPercentUsage
  else
    result := GetMaxPercentUsage;
end;

function TRbDrive.RecyclerIsNukeOnDeleteAutoDeterminate: boolean;
begin
  if TRecycleBinManager.RecyclerGroupPolicyNoRecycleFiles = gpEnabled then
    result := true
  else if TRecycleBinManager.UsesGlobalSettings then
    result := TRecycleBinManager.GetGlobalNukeOnDelete
  else
    result := GetNukeOnDelete;
end;

function TRbDrive.GetNukeOnDelete: boolean;
var
  reg: TRegistry;
  purgeInfo: TRbWin95PurgeInfo;
const
  RES_DEFAULT = false; // Windows 95 - Standardwert
begin
  result := RES_DEFAULT;

  reg := TRegistry.Create;
  try
    reg.RootKey := HKEY_LOCAL_MACHINE;

    // Im Auslieferungszustand von Windows 95 ist dieser Schl�ssel nicht vorhanden.
    // Er wird bei der ersten �nderung der Papierkorb-Einstellungen erstellt.
    if reg.OpenKeyReadOnly('SOFTWARE\Microsoft\Windows\CurrentVersion\explorer\BitBucket') then
    begin
      if reg.OpenKeyReadOnly(FDriveLetter) then
      begin
        if reg.ValueExists('NukeOnDelete') then
        begin
          // Windows 2000 - Informationen liegen aufgeschl�sselt in der Registry

          result := reg.ReadBool('NukeOnDelete');
        end;
      end
      else
      begin
        if reg.ValueExists('PurgeInfo') then
        begin
          // Windows 95 - Kodierte Informationen liegen in PurgeInfo

          reg.ReadBinaryData('PurgeInfo', purgeInfo, SizeOf(purgeInfo));

          result := ((purgeInfo.NukeOnDeleteBits shr DriveLetterToDriveNumber(FDriveLetter)) and 1) = 1;
        end;
      end;

      reg.CloseKey;
    end;
  finally
    reg.Free;
  end;
end;

function TRbDrive.GetNumItems: int64;
begin
  result := GetAPIInfo.i64NumItems;
end;

function TRbDrive.GetSize: int64;
begin
  result := GetAPIInfo.i64Size;
end;

function TRbDrive.GetVolumeGUID: TGUID;
begin
  if GetDriveGUID(FDriveLetter, result) <> ERROR_SUCCESS then
  begin
    result := NULL_GUID;
  end;
end;

function TRbDrive.IsEmpty: boolean;
begin
  result := GetNumItems = 0;
end;

function TRbDrive.IsFAT: boolean;
var
  Dummy2: DWORD;
  Dummy3: DWORD;
  FileSystem: array[0..MAX_PATH] of char;
  VolumeName: array[0..MAX_PATH] of char;
  s: string;
begin
  s := FDriveLetter + DriveDelim + PathDelim; // ohne die Auslagerung in einen String kommt es zu einer AV in ntdll
  GetVolumeInformation(PChar(s), VolumeName,
    SizeOf(VolumeName), nil, Dummy2, Dummy3, FileSystem, SizeOf(FileSystem));
  result := uppercase(copy(FileSystem, 0, 3)) = 'FAT';
end;

procedure TRbDrive.ListRecycleBins(list: TObjectList{TRbRecycleBin}; UserSID: string='');

  procedure _AddSIDFolders(dir: string; wholeFolder: boolean);
  var
    SR: TSearchRec;
  begin
    dir := IncludeTrailingPathDelimiter(dir);
    if FindFirst(dir+'S-*', faAnyFile, SR) = 0 then
    begin
      try
        repeat
          if (SR.Name = '.') or (SR.Name = '..') or not DirectoryExists(dir + SR.Name) then continue;

          if wholeFolder then
          begin
            // Vista
            list.Add(TRbRecycleBin.Create(dir+SR.Name, SR.Name));
          end
          else
          begin
            // Win95 .. WinXP
            if FileExists(IncludeTrailingPathDelimiter(dir+SR.Name) + 'INFO2') then
              list.Add(TRbRecycleBin.Create(IncludeTrailingPathDelimiter(dir+SR.Name) + 'INFO2', SR.Name));
            if FileExists(IncludeTrailingPathDelimiter(dir+SR.Name) + 'INFO') then
              list.Add(TRbRecycleBin.Create(IncludeTrailingPathDelimiter(dir+SR.Name) + 'INFO', SR.Name));
          end;
        until FindNext(SR) <> 0;
      finally
        FindClose(SR);
      end;
    end;
  end;

var
  dir: string;
begin
  // Find recyclers from Windows Vista or higher

  if IsFAT then
  begin
    dir := FDriveLetter + DriveDelim + PathDelim + '$recycle.bin' + PathDelim;
    if DirectoryExists(dir) then
    begin
      list.Add(TRbRecycleBin.Create(dir));
    end;
  end
  else
  begin
    if UserSID <> '' then
    begin
      dir := FDriveLetter + DriveDelim + PathDelim + '$recycle.bin' + PathDelim + UserSID + PathDelim;
      if DirectoryExists(dir) then
      begin
        list.Add(TRbRecycleBin.Create(dir, UserSID));
      end;
    end
    else
    begin
      _AddSIDFolders(FDriveLetter + DriveDelim + PathDelim + '$recycle.bin', true);
    end;
  end;

  // Find recyclers from Windows before Vista

  if IsFAT then
  begin
    dir := FDriveLetter + DriveDelim + PathDelim + 'Recycled' + PathDelim;

    // Both "recycle bins" are possible if you have multiboot (but do overwrite themselfes if you empty them)
    if FileExists(dir + 'INFO2') then
      list.Add(TRbRecycleBin.Create(dir + 'INFO2')); // Windows 95 with Internet Explorer 4 Extension or higher Windows versions
    if FileExists(dir + 'INFO') then
      list.Add(TRbRecycleBin.Create(dir + 'INFO')); // Windows 95 native
  end
  else
  begin
    if UserSID <> '' then
    begin
      dir := FDriveLetter + DriveDelim + PathDelim + 'Recycler' + PathDelim + UserSID + PathDelim;

      if FileExists(dir + 'INFO2') then
        list.Add(TRbRecycleBin.Create(dir + 'INFO2', UserSID));
      if FileExists(dir + 'INFO') then
        list.Add(TRbRecycleBin.Create(dir + 'INFO', UserSID)); // Windows NT 4
    end
    else
    begin
      _AddSIDFolders(FDriveLetter + DriveDelim + PathDelim + 'Recycler', false);
    end;
  end;
end;

{ TRbInfo1Item }

procedure TRbInfo1Item.ReadFromStream(stream: TStream);
var
  r: TRbInfoRecord;
begin
  stream.ReadBuffer(r, SizeOf(r));

  FSourceDrive := Chr(Ord('A') + r.sourceDrive);

  // This behavior will probably only happen with INFO2 files. Just to be sure,
  // we will also include the code here.
  if r.sourceAnsi[0] = #0 then
  begin
    FRemovedEntry := true;
    r.sourceAnsi[0] := FSourceDrive;
  end;

  FSourceAnsi := r.sourceAnsi;
  FSourceUnicode := r.sourceAnsi; // Unicode does not exist in INFO(1) structure
  FID := IntToStr(r.recordNumber);
  FDeletionTime := FileTimeToDateTime(r.deletionTime);
  FOriginalSize := r.originalSize;
end;

function TRbInfo1Item.DeleteFile: boolean;
var
  r: string;
begin
  r := GetPhysicalFile;
  if DirectoryExists(r) then
    result := DeleteDirectory(r) // Usually, the old recycle bin does not allow folders. Just to be sure, we include the code.
  else
    result := SysUtils.DeleteFile(r); // TODO: geht das oder gibt es zugriffsverletzung? --> Win95: Funktioniert

  // TODO: nun auch den eintrag aus der INFO-Datei rausschmei�en (Datei neu schreiben)
end;

function TRbInfo1Item.GetPhysicalFile: string;
begin
  if FRemovedEntry then
  begin
    result := '';
    Exit;
  end;

  // e.g. C:\...\DC0.doc
  result := IncludeTrailingPathDelimiter(ExtractFilePath(IndexFile)) +
            'D' + SourceDrive + ID + ExtractFileExt(SourceAnsi);
end;

constructor TRbInfo1Item.Create(fs: TStream; AIndexFile: string);
begin
  inherited Create;
  ReadFromStream(fs);
  FIndexFile := AIndexFile;
end;

{ TRbInfo2Item }

procedure TRbInfo2Item.ReadFromStream(stream: TStream);
var
  r: TRbInfo2Record;
begin
  stream.ReadBuffer(r, SizeOf(r));

  // Wenn ein Eintrag aus der INFO2 gel�scht wird, dann wird das erste Byte
  // von sourceAnsi auf Null gesetzt, damit die ganze INFO2 Datei nicht
  // st�ndig neu geschrieben werden muss.
  // Bei Win95/INFO wird der Eintrag komplett rausgel�scht und die INFO-Datei
  // daher neu geschrieben.
  // Wir lesen den Eintrag trotzdem, da unsere Software ja auch zu forensischen
  // Zwecken eingesetzt werden soll.
  if r.sourceAnsi[0] = #0 then
  begin
    FRemovedEntry := true;
    r.sourceAnsi[0] := AnsiChar(r.sourceUnicode[0]);
  end;

  FSourceAnsi := r.sourceAnsi;
  FSourceUnicode := r.sourceUnicode;
  FID := IntToStr(r.recordNumber);
  FSourceDrive := Chr(Ord('A') + r.sourceDrive);
  FDeletionTime := FileTimeToDateTime(r.deletionTime);
  FOriginalSize := r.originalSize;
end;

function TRbInfo2Item.DeleteFile: boolean;
var
  r: string;
begin
  r := GetPhysicalFile;
  if DirectoryExists(r) then
    result := DeleteDirectory(r)
  else
    result := SysUtils.DeleteFile(r); // TODO: geht das oder gibt es zugriffsverletzung?

  // TODO: nun auch den eintrag aus der INFO-Datei rausschmei�en (Erstes Byte auf 0 setzen)
end;

function TRbInfo2Item.GetPhysicalFile: string;
begin
  if FRemovedEntry then
  begin
    result := '';
    Exit;
  end;

  // e.g. C:\...\DC0.doc
  result := IncludeTrailingPathDelimiter(ExtractFilePath(IndexFile)) +
            'D' + SourceDrive + ID + ExtractFileExt(SourceUnicode);
end;

constructor TRbInfo2Item.Create(fs: TStream; AIndexFile: string);
begin
  inherited Create;
  ReadFromStream(fs);
  FIndexFile := AIndexFile;
end;

{ TRbVistaItem }

procedure TRbVistaItem.ReadFromStream(stream: TStream);
var
  r: TRbVistaRecord;
begin
  stream.ReadBuffer(r, SizeOf(r));

  FSourceAnsi := AnsiString(r.sourceUnicode); // Invalid chars are automatically converted into '?'
  FSourceUnicode := r.sourceUnicode;
  FID := ''; // will be added manually (at the constructor)
  FSourceDrive := AnsiChar(r.sourceUnicode[1]);
  FDeletionTime := FileTimeToDateTime(r.deletionTime);
  FOriginalSize := r.originalSize;
end;

function TRbVistaItem.DeleteFile: boolean;
var
  r: string;
begin
  r := GetPhysicalFile;
  if DirectoryExists(r) then
    result := DeleteDirectory(r)
  else
    result := SysUtils.DeleteFile(r);

  SysUtils.DeleteFile(FIndexFile);
end;

function TRbVistaItem.GetPhysicalFile: string;
begin
  result := FIndexFile;
  result := StringReplace(Result, '$I', '$R', [rfIgnoreCase]);
end;

constructor TRbVistaItem.Create(fs: TStream; AIndexFile, AID: string);
begin
  inherited Create;
  ReadFromStream(fs);
  FIndexFile := AIndexFile;
  FID := AID;
end;

{ TRecycleBinManager }

class function TRecycleBinManager.EmptyOwnRecyclers(flags: cardinal): boolean;
var
  PSHEmptyRecycleBin: TSHEmptyRecycleBin;
  LibHandle: THandle;
begin
  // Source: http://www.dsdt.info/tipps/?id=176
  result := true;
  LibHandle := LoadLibrary(shell32);
  try
    if LibHandle <> 0 then
    begin
      @PSHEmptyRecycleBin := GetProcAddress(LibHandle, C_SHEmptyRecycleBinA);
      if @PSHEmptyRecycleBin <> nil then
      begin
        PSHEmptyRecycleBin(hInstance, nil, flags);
      end
      else
        result := false;
    end
    else
      result := false;
  finally
    @PSHEmptyRecycleBin := nil;
    if LibHandle <> 0 then FreeLibrary(LibHandle);
  end;
end;

class function TRecycleBinManager.EmptyOwnRecyclers(sound, progress, confirmation: boolean): boolean;
const
  SHERB_NOCONFIRMATION = $00000001;
  SHERB_NOPROGRESSUI   = $00000002;
  SHERB_NOSOUND        = $00000004;
var
  flags: cardinal;
begin
  flags := 0;

  if not progress then
    flags := flags or SHERB_NOPROGRESSUI;
  if not confirmation then
    flags := flags or SHERB_NOCONFIRMATION;
  if not sound then
    flags := flags or SHERB_NOSOUND;

  result := EmptyOwnRecyclers(flags);
end;

class function TRecycleBinManager.GetGlobalMaxPercentUsage: integer;
var
  reg: TRegistry;
  purgeInfo: TRbWin95PurgeInfo;
const
  RES_DEFAULT = 10; // Windows 95 - Standardwert
begin
  result := RES_DEFAULT;

  reg := TRegistry.Create;
  try
    reg.RootKey := HKEY_LOCAL_MACHINE;

    // Im Auslieferungszustand von Windows 95 ist dieser Schl�ssel nicht vorhanden.
    // Er wird bei der ersten �nderung der Papierkorb-Einstellungen erstellt.
    if reg.OpenKeyReadOnly('SOFTWARE\Microsoft\Windows\CurrentVersion\explorer\BitBucket') then
    begin
      if reg.ValueExists('Percent') then
      begin
        // Windows 2000 - Informationen liegen aufgeschl�sselt in der Registry

        result := reg.ReadInteger('Percent');
      end
      else if reg.ValueExists('PurgeInfo') then
      begin
        // Windows 95 - Kodierte Informationen liegen in PurgeInfo

        reg.ReadBinaryData('PurgeInfo', purgeInfo, SizeOf(purgeInfo));
        result := purgeInfo.percentGlobal;
      end;

      reg.CloseKey;
    end;
  finally
    reg.Free;
  end;
end;

class function TRecycleBinManager.GetGlobalNukeOnDelete: boolean;
var
  reg: TRegistry;
  purgeInfo: TRbWin95PurgeInfo;
const
  RES_DEFAULT = false; // Windows 95 - Standardwert
begin
  result := RES_DEFAULT;

  reg := TRegistry.Create;
  try
    reg.RootKey := HKEY_LOCAL_MACHINE;

    // Im Auslieferungszustand von Windows 95 ist dieser Schl�ssel nicht vorhanden.
    // Er wird bei der ersten �nderung der Papierkorb-Einstellungen erstellt.
    if reg.OpenKeyReadOnly('SOFTWARE\Microsoft\Windows\CurrentVersion\explorer\BitBucket') then
    begin
      if reg.ValueExists('NukeOnDelete') then
      begin
        // Windows 2000 - Informationen liegen aufgeschl�sselt in der Registry

        result := reg.ReadBool('NukeOnDelete');
      end
      else if reg.ValueExists('PurgeInfo') then
      begin
        // Windows 95 - Kodierte Informationen liegen in PurgeInfo

        reg.ReadBinaryData('PurgeInfo', purgeInfo, SizeOf(purgeInfo));
        result := (purgeInfo.NukeOnDeleteBits and $8000000) = $8000000; // bit 27
      end;

      reg.CloseKey;
    end;
  finally
    reg.Free;
  end;
end;

class function TRecycleBinManager.UsesGlobalSettings: boolean;
var
  reg: TRegistry;
  purgeInfo: TRbWin95PurgeInfo;
const
  RES_DEFAULT = true; // Windows 95 - Standardwert
begin
  result := RES_DEFAULT;

  reg := TRegistry.Create;
  try
    reg.RootKey := HKEY_LOCAL_MACHINE;

    // Im Auslieferungszustand von Windows 95 ist dieser Schl�ssel nicht vorhanden.
    // Er wird bei der ersten �nderung der Papierkorb-Einstellungen erstellt.
    if reg.OpenKeyReadOnly('SOFTWARE\Microsoft\Windows\CurrentVersion\explorer\BitBucket') then
    begin
      if reg.ValueExists('UseGlobalSettings') then
      begin
        // Windows 2000 - Informationen liegen aufgeschl�sselt in der Registry

        result := reg.ReadBool('UseGlobalSettings');
      end
      else if reg.ValueExists('PurgeInfo') then
      begin
        // Windows 95 - Kodierte Informationen liegen in PurgeInfo

        reg.ReadBinaryData('PurgeInfo', purgeInfo, SizeOf(purgeInfo));
        result := purgeInfo.bGlobalSettings;
      end;

      reg.CloseKey;
    end;
  finally
    reg.Free;
  end;
end;

class procedure TRecycleBinManager.ListDrives(list: TObjectList{TRbDrive});
var
  drive: Char;
begin
  for drive := 'A' to 'Z' do
    if RecycleBinPossible(drive) then
      list.Add(TRbDrive.Create(drive));
end;

class function TRecycleBinManager.OwnRecyclersEmpty: boolean;
var
  drives: TObjectList;
  i: integer;
begin
  result := true;

  drives := TObjectList.Create(true);
  try
    ListDrives(drives);
    for i := 0 to drives.Count - 1 do
    begin
      result := result and TRbDrive(drives.Items[i]).IsEmpty;
      if not result then break;
    end;
  finally
    drives.Free;
  end;
end;

class function TRecycleBinManager.OwnRecyclersNumItems: int64;
var
  drives: TObjectList;
  i: integer;
begin
  result := 0;

  drives := TObjectList.Create(true);
  try
    ListDrives(drives);
    for i := 0 to drives.Count - 1 do
    begin
      result := result + TRbDrive(drives.Items[i]).GetNumItems;
    end;
  finally
    drives.Free;
  end;
end;

class function TRecycleBinManager.OwnRecyclersSize: int64;
var
  drives: TObjectList;
  i: integer;
begin
  result := 0;

  drives := TObjectList.Create(true);
  try
    ListDrives(drives);
    for i := 0 to drives.Count - 1 do
    begin
      result := result + TRbDrive(drives.Items[i]).GetSize;
    end;
  finally
    drives.Free;
  end;
end;

class function TRecycleBinManager.RecycleBinPossible(Drive: Char): boolean;
var
  typ: Integer;
begin
  // Does the drive exist?
  // see http://www.delphipraxis.net/post2933.html
  result := GetLogicalDrives and (1 shl DriveLetterToDriveNumber(Drive)) <> 0;
  if not result then exit;

  // Is it a fixed drive? (Only they can have recycle bins)
  // TODO: is that correct, or can also have other drive types have recyclers?
  typ := GetDriveType(PChar(Drive + ':\'));
  result := typ = DRIVE_FIXED;
end;

class function TRecycleBinManager.RecyclerGetCurrentIconString: string;
begin
  if OwnRecyclersEmpty then
    result := RecyclerGetEmptyIconString
  else
    result := RecyclerGetFullIconString;
end;

class function TRecycleBinManager.RecyclerGetDefaultIconString: string;
var
  reg: TRegistry;
begin
  // Please note: The "default" icon is not always the icon of the
  // current recycle bin in its current state (full, empty)
  // At Windows 95b, the registry value actually did change every time the
  // recycle bin state did change, but at Windows 2000 I could not see any
  // update, even after reboot. So, the registry value is possible fixed as
  // default = empty on newer OS versions.

  reg := TRegistry.Create;
  try
    reg.RootKey := HKEY_CLASSES_ROOT;
    if reg.OpenKeyReadOnly('CLSID\'+GUIDToString(RECYCLER_CLSID)+'\DefaultIcon') then
    begin
      result := reg.ReadString('');
      reg.CloseKey;
    end;
  finally
    reg.Free;
  end;
end;

class function TRecycleBinManager.RecyclerGetEmptyIconString: string;
var
  reg: TRegistry;
begin
  reg := TRegistry.Create;
  try
    reg.RootKey := HKEY_CLASSES_ROOT;
    if reg.OpenKeyReadOnly('CLSID\'+GUIDToString(RECYCLER_CLSID)+'\DefaultIcon') then
    begin
      result := reg.ReadString('Empty');
      reg.CloseKey;
    end;
  finally
    reg.Free;
  end;
end;

class function TRecycleBinManager.RecyclerGetFullIconString: string;
var
  reg: TRegistry;
begin
  reg := TRegistry.Create;
  try
    reg.RootKey := HKEY_CLASSES_ROOT;
    if reg.OpenKeyReadOnly('CLSID\'+GUIDToString(RECYCLER_CLSID)+'\DefaultIcon') then
    begin
      result := reg.ReadString('Full');
      reg.CloseKey;
    end;
  finally
    reg.Free;
  end;
end;

class function TRecycleBinManager.RecyclerGetInfoTip: string;
var
  reg: TRegistry;
begin
  // Not available in some older versions of Windows

  reg := TRegistry.Create;
  try
    reg.RootKey := HKEY_CLASSES_ROOT;
    if reg.OpenKeyReadOnly('CLSID\'+GUIDToString(RECYCLER_CLSID)) then
    begin
      result := reg.ReadString('InfoTip');
      result := DecodeReferenceString(result);

      reg.CloseKey;
    end;
  finally
    reg.Free;
  end;
end;

class function TRecycleBinManager.RecyclerGetIntroText: string;
var
  reg: TRegistry;
begin
  // Not available in some older versions of Windows

  reg := TRegistry.Create;
  try
    reg.RootKey := HKEY_CLASSES_ROOT;
    if reg.OpenKeyReadOnly('CLSID\'+GUIDToString(RECYCLER_CLSID)) then
    begin
      result := reg.ReadString('IntroText');
      result := DecodeReferenceString(result);

      reg.CloseKey;
    end;
  finally
    reg.Free;
  end;
end;

class function TRecycleBinManager.RecyclerGetName: string;
var
  reg: TRegistry;
begin
  // Windows 95b:
  // Change of CLSID\{645FF040-5081-101B-9F08-00AA002F954E} will change the desktop name of the recycle bin.

  // Windows 2000: If LocalizedString is available, the 3rd argument will be parsed
  // (if the third argument will removed, it will be read out from the DLL resource string automatically)

  reg := TRegistry.Create;
  try
    reg.RootKey := HKEY_CLASSES_ROOT;
    if reg.OpenKeyReadOnly('CLSID\'+GUIDToString(RECYCLER_CLSID)) then
    begin
      if reg.ValueExists('LocalizedString') then
      begin
        result := reg.ReadString('LocalizedString');
        result := DecodeReferenceString(result);
      end
      else
      begin
        result := reg.ReadString('');
      end;

      reg.CloseKey;
    end;
  finally
    reg.Free;
  end;
end;

class function TRecycleBinManager.RecyclerEmptyEventGetName: string;
var
  reg: TRegistry;
begin
  reg := TRegistry.Create;
  try
    reg.RootKey := HKEY_CURRENT_USER;
    if reg.OpenKeyReadOnly('AppEvents\EventLabels\EmptyRecycleBin') then
    begin
      result := reg.ReadString('');
      reg.CloseKey;
    end;
  finally
    reg.Free;
  end;
end;

class function TRecycleBinManager.RecyclerEmptyEventGetCurrentSound: string;
begin
  result := RecyclerEmptyEventGetSound('.Current');
end;

class function TRecycleBinManager.RecyclerEmptyEventGetDefaultSound: string;
begin
  result := RecyclerEmptyEventGetSound('.Default');
end;

class procedure TRecycleBinManager.RecyclerEmptyEventGetSoundCategories(AStringList: TStringList);
var
  reg: TRegistry;
begin
  reg := TRegistry.Create;
  try
    reg.RootKey := HKEY_CURRENT_USER;
    if reg.OpenKeyReadOnly('AppEvents\Schemes\Apps\Explorer\EmptyRecycleBin') then
    begin
      reg.GetKeyNames(AStringList);
      reg.CloseKey;
    end;
  finally
    reg.Free;
  end;
end;

class function TRecycleBinManager.RecyclerEmptyEventGetSound(ACategory: string): string;
var
  reg: TRegistry;
resourcestring
  LNG_SND_EVENT_CAT_ERROR = 'The category "%s" is not available for the notification event "%s".';
begin
  // Outputs an filename or empty string for no sound defined.

  reg := TRegistry.Create;
  try
    reg.RootKey := HKEY_CURRENT_USER;
    if reg.OpenKeyReadOnly('AppEvents\Schemes\Apps\Explorer\EmptyRecycleBin') then
    begin
      if reg.OpenKeyReadOnly(ACategory) then
      begin
        result := reg.ReadString('');
        reg.CloseKey;
      end
      else
        raise EEventCategoryNotDefined.CreateFmt(LNG_SND_EVENT_CAT_ERROR, [ACategory, 'EmptyRecycleBin']);
      reg.CloseKey;
    end;
  finally
    reg.Free;
  end;
end;

class function TRecycleBinManager.RecyclerQueryFunctionAvailable: boolean;
var
  RBHandle: THandle;
  SHQueryRecycleBin: TSHQueryRecycleBin;
begin
  // Windows 95 without Internet Explorer 4 has no SHQueryRecycleBinA.
  RBHandle := LoadLibrary(shell32);
  try
    if RBHandle <> 0 then
    begin
      SHQueryRecycleBin := GetProcAddress(RBHandle, C_SHQueryRecycleBin);
      if not Assigned(@SHQueryRecycleBin) then
      begin
        FreeLibrary(RBHandle);
        RBHandle := 0;
      end;
    end;

    result := RBHandle <> 0;
  finally
    if RBHandle <> 0 then FreeLibrary(RBHandle);
  end;
end;

class function TRecycleBinManager.RecyclerAddFileOrFolder(FileOrFolder: string; confirmation: boolean=false): boolean;
var
  Operation: TSHFileOpStruct;
begin
  // Template: http://www.dsdt.info/tipps/?id=116
  with Operation do
  begin
    Wnd := hInstance; // OK?
    wFunc := FO_DELETE;
    pFrom := PChar(FileOrFolder + #0);
    pTo := nil;
    fFlags := FOF_ALLOWUNDO;
    if not confirmation then fFlags := fFlags or FOF_NOCONFIRMATION;
  end;
  Result := SHFileOperation(Operation) = 0;
end;

class function TRecycleBinManager.RecyclerGroupPolicyNoRecycleFiles: GPOLICYBOOL;
var
  reg: TRegistry;
begin
  result := gpUndefined;

  reg := TRegistry.Create;
  try
    // If a value is set in HKEY_LOCAL_MACHINE, it will be prefered,
    // even if gpedit.msc shows "Not configured"!
    {$IFDEF GroupPolicyAcceptHKLMTrick}
    reg.RootKey := HKEY_LOCAL_MACHINE;
    if reg.OpenKeyReadOnly('Software\Microsoft\Windows\CurrentVersion\Policies\Explorer') then
    begin
      if reg.ValueExists('NoRecycleFiles') then
      begin
        if reg.ReadBool('NoRecycleFiles') then
          result := gpEnabled
        else
          result := gpDisabled;
        Exit;
      end;
      reg.CloseKey;
    end;
    {$ENDIF}

    reg.RootKey := HKEY_CURRENT_USER;
    if reg.OpenKeyReadOnly('Software\Microsoft\Windows\CurrentVersion\Policies\Explorer') then
    begin
      if reg.ValueExists('NoRecycleFiles') then
      begin
        if reg.ReadBool('NoRecycleFiles') then
          result := gpEnabled
        else
          result := gpDisabled;
      end;
      reg.CloseKey;
    end;
  finally
    reg.Free;
  end;
end;

class function TRecycleBinManager.RecyclerGroupPolicyConfirmFileDelete: GPOLICYBOOL;
var
  reg: TRegistry;
begin
  result := gpUndefined;
  reg := TRegistry.Create;
  try
    // If a value is set in HKEY_LOCAL_MACHINE, it will be prefered,
    // even if gpedit.msc shows "Not configured"!
    {$IFDEF GroupPolicyAcceptHKLMTrick}
    reg.RootKey := HKEY_LOCAL_MACHINE;
    if reg.OpenKeyReadOnly('Software\Microsoft\Windows\CurrentVersion\Policies\Explorer') then
    begin
      if reg.ValueExists('ConfirmFileDelete') then
      begin
        if reg.ReadBool('ConfirmFileDelete') then
          result := gpEnabled
        else
          result := gpDisabled;
        Exit;
      end;
      reg.CloseKey;
    end;
    {$ENDIF}

    reg.RootKey := HKEY_CURRENT_USER;
    if reg.OpenKeyReadOnly('Software\Microsoft\Windows\CurrentVersion\Policies\Explorer') then
    begin
      if reg.ValueExists('ConfirmFileDelete') then
      begin
        if reg.ReadBool('ConfirmFileDelete') then
          result := gpEnabled
        else
          result := gpDisabled;
      end;
      reg.CloseKey;
    end;
  finally
    reg.Free;
  end;
end;

class function TRecycleBinManager.RecyclerGroupPolicyRecycleBinSize: integer;
var
  reg: TRegistry;
begin
  result := -1;
  reg := TRegistry.Create;
  try
    // If a value is set in HKEY_LOCAL_MACHINE, it will be prefered,
    // even if gpedit.msc shows "Not configured"!
    {$IFDEF GroupPolicyAcceptHKLMTrick}
    reg.RootKey := HKEY_LOCAL_MACHINE;
    if reg.OpenKeyReadOnly('Software\Microsoft\Windows\CurrentVersion\Policies\Explorer') then
    begin
      if reg.ValueExists('RecycleBinSize') then
      begin
        result := reg.ReadInteger('RecycleBinSize');
        Exit;
      end;
      reg.CloseKey;
    end;
    {$ENDIF}

    reg.RootKey := HKEY_CURRENT_USER;
    if reg.OpenKeyReadOnly('Software\Microsoft\Windows\CurrentVersion\Policies\Explorer') then
    begin
      if reg.ValueExists('RecycleBinSize') then
      begin
        result := reg.ReadInteger('RecycleBinSize');
      end;
      reg.CloseKey;
    end;
  finally
    reg.Free;
  end;
end;

class function TRecycleBinManager.RecyclerConfirmationDialogEnabled: boolean;
var
  gp: GPOLICYBOOL;
begin
  gp := RecyclerGroupPolicyConfirmFileDelete;
  if gp <> gpUndefined then
  begin
    result := gp = gpEnabled;
  end
  else
  begin
    result := RecyclerShellStateConfirmationDialogEnabled;
  end;
end;

class function TRecycleBinManager.RecyclerShellStateConfirmationDialogEnabled: boolean;
var
  lpss: SHELLSTATE;
  bNoConfirmRecycle: boolean;

  PSHGetSettings: TSHGetSettings;
  RBHandle: THandle;

  reg: TRegistry;
  rbuf: array[0..255] of byte;
begin
  PSHGetSettings := nil;
  result := false; // Avoid warning message

  RBHandle := LoadLibrary(shell32);
  try
    if RBHandle <> 0 then
    begin
      PSHGetSettings := GetProcAddress(RBHandle, C_SHGetSettings);
      if not Assigned(@PSHGetSettings) then
      begin
        FreeLibrary(RBHandle);
        RBHandle := 0;
      end;
    end;

    if (RBHandle <> 0) and Assigned(PSHGetSettings) then
    begin
      ZeroMemory(@lpss, SizeOf(lpss));
      PSHGetSettings(lpss, SSF_NOCONFIRMRECYCLE);
      bNoConfirmRecycle := (lpss.Flags1 and 4) = 4; // fNoConfirmRecycle

      result := not bNoConfirmRecycle;
    end
    else
    begin
      reg := TRegistry.Create;
      try
        // API function call failed. Probably because Windows is too old.
        // Try to read out from registry.
        // The 3rd bit of the 5th byte of "ShellState" is the value
        // of "fNoConfirmRecycle".

        reg.RootKey := HKEY_CURRENT_USER;
        if reg.OpenKeyReadOnly('Software\Microsoft\Windows\CurrentVersion\Explorer') then
        begin
          ZeroMemory(@rbuf, SizeOf(rbuf));
          reg.ReadBinaryData('ShellState', rbuf, SizeOf(rbuf));

          // Lese 3tes Bit vom 5ten Byte
          bNoConfirmRecycle := ((rbuf[4] and 4) = 4);
          result := not bNoConfirmRecycle;

          reg.CloseKey;
        end
        else
        begin
          raise EAPICallError.CreateFmt(LNG_API_CALL_ERROR, [Format(LNG_NOT_CALLABLE, [C_SHGetSettings])]);
        end;
      finally
        reg.Free;
      end;
    end;
  finally
    if RBHandle <> 0 then FreeLibrary(RBHandle);
  end;
end;

class procedure TRecycleBinManager.RecyclerConfirmationDialogSetEnabled(NewSetting: boolean);
var
  lpss: SHELLSTATE;

  PSHGetSetSettings: TSHGetSetSettings;
  RBHandle: THandle;

  reg: TRegistry;
  rbuf: array[0..255] of byte;

  dwResult: DWORD;
begin
  PSHGetSetSettings := nil;

  RBHandle := LoadLibrary(shell32);
  try
    if RBHandle <> 0 then
    begin
      PSHGetSetSettings := GetProcAddress(RBHandle, C_SHGetSetSettings);
      if not Assigned(@PSHGetSetSettings) then
      begin
        FreeLibrary(RBHandle);
        RBHandle := 0;
      end;
    end;

    if (RBHandle <> 0) and Assigned(PSHGetSetSettings) then
    begin
      ZeroMemory(@lpss, SizeOf(lpss));

      PSHGetSetSettings(lpss, SSF_NOCONFIRMRECYCLE, false); // Get

      // Set 3rd bit equal to NewSetting
      if NewSetting then
        lpss.Flags1 := lpss.Flags1 or  $00000004
      else
        lpss.Flags1 := lpss.Flags1 and $FFFFFFFB;

      PSHGetSetSettings(lpss, SSF_NOCONFIRMRECYCLE, true); // Set

      SendMessageTimeout (
        HWND_BROADCAST, WM_SETTINGCHANGE,
        0, lParam (pChar ('ShellState')),
        SMTO_ABORTIFHUNG, 5000, dwResult
      );
    end
    else
    begin
      reg := TRegistry.Create;
      try
        // API function call failed. Probably because Windows is too old.
        // Try to read out from registry.
        // The 3rd bit of the 5th byte of "ShellState" is the value
        // of "fNoConfirmRecycle".

        reg.RootKey := HKEY_CURRENT_USER;
        if reg.OpenKey('Software\Microsoft\Windows\CurrentVersion\Explorer', false) then
        begin
          ZeroMemory(@rbuf, SizeOf(rbuf));

          reg.ReadBinaryData('ShellState', rbuf, SizeOf(rbuf)); // Get

          // Set 3rd bit equal to NewSetting
          if NewSetting then
            rbuf[4] := rbuf[4] or  $04
          else
            rbuf[4] := rbuf[4] and $FB;

          reg.WriteBinaryData('ShellState', rbuf, SizeOf(rbuf)); // Set

          SendMessageTimeout (
            HWND_BROADCAST, WM_SETTINGCHANGE,
            0, lParam (pChar ('ShellState')),
            SMTO_ABORTIFHUNG, 5000, dwResult
          );

          reg.CloseKey;
        end
        else
        begin
          raise EAPICallError.CreateFmt(LNG_API_CALL_ERROR, [Format(LNG_NOT_CALLABLE, [C_SHGetSetSettings])]);
        end;
      finally
        reg.Free;
      end;
    end;
  finally
    if RBHandle <> 0 then FreeLibrary(RBHandle);
  end;
end;

{ TRbRecycleBinItem }

function TRbRecycleBinItem.GetSource: string;
begin
  {$IFDEF UNICODE}
  result := SourceUnicode;
  {$ELSE}
  result := SourceAnsi;
  {$ENDIF}
end;

end.
unit UMenu;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, ActnList, Forms, Menus, UTool, LCLType, ExtCtrls, UConfig,
  Controls, LazPaintType;

type

  { TMainFormMenu }

  TMainFormMenu = class
  private
    FActionList: TActionList;
    FDarkTheme: boolean;
    FMainMenus: array of TMenuItem;
    FToolsShortcuts: array[TPaintToolType] of TUTF8Char;
    FToolbars: array of record
                 tb: TPanel;
                 fixed: boolean;
               end;
    FToolbarsHeight : integer;
    FToolbarBackground: TPanel;
    FImageList: TImageList;
    procedure IconSizeItemClick(Sender: TObject);
    procedure IconSizeMenuClick(Sender: TObject);
    procedure SetDarkTheme(AValue: boolean);
  protected
    FInstance: TLazPaintCustomInstance;
    procedure AddMenus(AMenu: TMenuItem; AActionList: TActionList; AActionsCommaText: string; AIndex: integer = -1); overload;
    procedure AddMenus(AMenuName: string; AActionsCommaText: string); overload;
    procedure ApplyShortcuts;
    procedure ActionShortcut(AName: string; AShortcut: TUTF8Char);
    procedure ApplyTheme;
  public
    constructor Create(AInstance: TLazPaintCustomInstance; AActionList: TActionList);
    procedure PredefinedMainMenus(const AMainMenus: array of TMenuItem);
    procedure Toolbars(const AToolbars: array of TPanel; AToolbarBackground: TPanel);
    procedure CycleTool(var ATool: TPaintToolType; var AShortCut: TUTF8Char);
    procedure Apply;
    procedure ArrangeToolbars(ClientWidth: integer);
    procedure RepaintToolbar;
    property ToolbarsHeight: integer read FToolbarsHeight;
    property ImageList: TImageList read FImageList write FImageList;
    property DarkTheme: boolean read FDarkTheme write SetDarkTheme;
  end;

implementation

uses UResourceStrings, BGRAUTF8, LCScaleDPI, ComCtrls, Graphics,
  Spin, StdCtrls, BGRAText, math, udarktheme;

{ TMainFormMenu }

procedure TMainFormMenu.IconSizeMenuClick(Sender: TObject);
var
  menu: TMenuItem;
  i, iconSize: Integer;
begin
  menu := Sender as TMenuItem;
  iconSize := FInstance.Config.DefaultIconSize(0);
  for i := 0 to menu.Count-1 do
    menu.Items[i].Checked := (menu.Items[i].Tag = iconSize);
end;

procedure TMainFormMenu.SetDarkTheme(AValue: boolean);
begin
  if FDarkTheme=AValue then Exit;
  FDarkTheme:=AValue;
  ApplyTheme;
end;

procedure TMainFormMenu.IconSizeItemClick(Sender: TObject);
var
  item: TMenuItem;
begin
  item:= Sender as TMenuItem;
  FInstance.ChangeIconSize(item.Tag);
end;

procedure TMainFormMenu.AddMenus(AMenu: TMenuItem; AActionList: TActionList;
  AActionsCommaText: string; AIndex: integer);
var actions: TStringList;
  foundAction: TBasicAction;
  item: TMenuItem;
  i,j: NativeInt;

  procedure AddSubItem(ACaption: string; AOnClick: TNotifyEvent; ATag: integer);
  var
    subItem: TMenuItem;
  begin
    subItem := TMenuItem.Create(item);
    subItem.Caption := ACaption;
    subItem.Tag := ATag;
    subItem.OnClick := AOnClick;
    item.Add(subItem);
  end;

begin
  actions := TStringList.Create;
  actions.CommaText := AActionsCommaText;
  for i := 0 to actions.Count-1 do
    if (actions[i]='*') and (AIndex = -1) then
      AIndex := 0;
  for i := 0 to actions.Count-1 do
  begin
    if actions[i]='*' then
    begin
      AIndex := -1;
      Continue;
    end;
    item := TMenuItem.Create(nil);
    if trim(actions[i]) = '-' then
      item.Caption := cLineCaption
    else
    begin
      foundAction := AActionList.ActionByName(actions[i]);
      if foundAction <> nil then
        item.Action := foundAction
      else
      begin
        for j := 0 to AMenu.Count-1 do
          if UTF8CompareText(AMenu.Items[j].Name,actions[i])=0 then
          begin
            FreeAndNil(item);
            AMenu.Items[j].Visible := true;
            if (AIndex <> -1) and (AIndex < j) then
            begin
              item := AMenu.Items[j];
              AMenu.Remove(item);
              AMenu.Insert(AIndex,item);
              item := nil;
              inc(AIndex);
            end else
            if AIndex = -1 then
            begin
              item := AMenu.Items[j];
              AMenu.Remove(item);
              AMenu.Add(item);
              item := nil;
            end;
            break;
          end;
        if Assigned(item) and (actions[i] = 'MenuIconSize') then
        begin
          item.Caption := rsIconSize;
          item.OnClick:=@IconSizeMenuClick;
          AddSubItem('16px', @IconSizeItemClick, 16);
          AddSubItem('24px', @IconSizeItemClick, 24);
          AddSubItem('32px', @IconSizeItemClick, 32);
          AddSubItem('48px', @IconSizeItemClick, 48);
          AddSubItem(rsAutodetect, @IconSizeItemClick, 0);
          AMenu.Add(item);
          item := nil;
        end;
        if Assigned(item) then item.Caption := trim(actions[i])+'?';
      end;
    end;
    if Assigned(item) then
    begin
      if AIndex = -1 then
        AMenu.Add(item)
      else
      begin
        AMenu.Insert(AIndex,item);
        inc(AIndex);
      end;
    end;
  end;
  actions.Free;
end;

procedure TMainFormMenu.AddMenus(AMenuName: string; AActionsCommaText: string);
var i: NativeInt;
begin
  for i := 0 to MenuDefinitionKeys.count-1 do
    if UTF8CompareText(MenuDefinitionKeys[i],AMenuName)=0 then
    begin
      AActionsCommaText:= MenuDefinitionValues[i];
      if AActionsCommaText = '' then exit;
      break;
    end;
  for i := 0 to high(FMainMenus) do
    if FMainMenus[i].Name = AMenuName then
    begin
      AddMenus(FMainMenus[i], FActionList, AActionsCommaText);
      FMainMenus[i].Visible := true;
    end;
end;

procedure TMainFormMenu.ActionShortcut(AName: string; AShortcut: TUTF8Char);
var foundAction: TBasicAction;
  ShortcutStr: string;
begin
  foundAction := FActionList.ActionByName(AName);
  if foundAction <> nil then
  begin
    ShortcutStr := AShortcut;
    if (length(AName) >= 5) and (copy(AName,1,4) = 'Tool') and
        (AName[5] = upcase(AName[5])) then
      FToolsShortcuts[StrToPaintToolType(copy(AName,5,length(AName)-4))] := AShortcut;
    AppendShortcut(foundAction as TAction, ShortcutStr);
  end;
end;

procedure TMainFormMenu.ApplyTheme;
var
  i, j: Integer;
begin
  for i := 0 to high(FToolbars) do
  begin
    with FToolbars[i].tb do
    begin
      DarkThemeInstance.Apply(FToolbars[i].tb, DarkTheme);
      for j := 0 to ControlCount-1 do
        if Controls[j] is TToolBar then
        begin
          if FDarkTheme then
          begin
            Controls[j].Color := clDarkBtnFace;
            TToolbar(Controls[j]).OnPaintButton:= @DarkThemeInstance.ToolBarPaintButton;
          end
          else
          begin
            Controls[j].Color := clBtnFace;
            TToolbar(Controls[j]).OnPaintButton:= nil;
          end;
        end else
        if Controls[j] is TLabel then
        begin
          if (Controls[j].Name = 'Label_Coordinates') or
             (Controls[j].Name = 'Label_CurrentZoom') or
             (Controls[j].Name = 'Label_CurrentDiff') then
          begin
            if FDarkTheme then
            begin
              Controls[j].Color := clDarkBtnFace;
              Controls[j].Font.Color := clLightText;
            end
            else
            begin
              Controls[j].Color := clWhite;
              Controls[j].Font.Color := clBlack;
            end;
          end else
          begin
            if FDarkTheme then
              Controls[j].Font.Color := clLightText
            else
              Controls[j].Font.Color := clBlack;
          end;
        end;
    end;
  end;
  if Assigned(FToolbarBackground) then
  begin
    if FDarkTheme then
      FToolbarBackground.Color := clDarkBtnFace
    else
      FToolbarBackground.Color := clBtnFace;
  end;
end;

constructor TMainFormMenu.Create(AInstance: TLazPaintCustomInstance; AActionList: TActionList);
begin
  FInstance := AInstance;
  FActionList := AActionList;
  FToolbarsHeight := 0;
end;

procedure TMainFormMenu.PredefinedMainMenus(const AMainMenus: array of TMenuItem);
var i: NativeInt;
begin
  setlength(FMainMenus, length(AMainMenus));
  for i := 0 to high(AMainMenus) do
    FMainMenus[i] := AMainMenus[i];
end;

procedure TMainFormMenu.Toolbars(const AToolbars: array of TPanel; AToolbarBackground: TPanel);
var i,j: NativeInt;
begin
  setlength(FToolbars, length(AToolbars));
  for i := 0 to high(FToolbars) do
  begin
    FToolbars[i].tb := AToolbars[i];
    FToolbars[i].tb.Cursor := crArrow;
    with FToolbars[i].tb do
    for j := 0 to ControlCount-1 do
    begin
      Controls[j].Cursor := crArrow;
      if Controls[j] is TLabel then
      begin
        if (Controls[j].Name = 'Label_Coordinates') or
           (Controls[j].Name = 'Label_CurrentZoom') or
           (Controls[j].Name = 'Label_CurrentDiff') then
          Controls[j].Font.Size := Controls[j].Height*38 div ScreenInfo.PixelsPerInchY
        else
          Controls[j].Font.Size := Controls[j].Height*33 div ScreenInfo.PixelsPerInchY;
      end;
    end;
  end;
  FToolbarBackground := AToolbarBackground;
end;

procedure TMainFormMenu.CycleTool(var ATool: TPaintToolType;
  var AShortCut: TUTF8Char);
var
  curTool: TPaintToolType;
begin
  AShortCut := UTF8UpperCase(AShortCut);
  curTool := ATool;
  repeat
    if curTool = high(TPaintToolType) then
      curTool := low(TPaintToolType)
    else
      curTool := succ(curTool);

    if FToolsShortcuts[curTool] = AShortCut then
    begin
      ATool := curTool;
      AShortCut:= '';
      exit;
    end;
  until curTool = ATool;
end;

procedure TMainFormMenu.Apply;
const ImageBrowser = {$IFNDEF DARWIN}'FileUseImageBrowser,'{$ELSE}''{$ENDIF};
var i,j,tbHeight,tbHeightOrig: NativeInt;
begin
  for i := 0 to FActionList.ActionCount-1 do
  with FActionList.Actions[i] as TAction do
    if (Caption = '') and (Hint <> '') then Caption := Hint;

  AddMenus('MenuFile',   'FileNew,FileOpen,LayerFromFile,MenuRecentFiles,FileChooseEntry,FileReload,-,FileSave,FileSaveAsInSameFolder,FileSaveAs,-,FileImport3D,-,FilePrint,-,'+ImageBrowser+'FileRememberSaveFormat,ForgetDialogAnswers,MenuLanguage,*');
  AddMenus('MenuEdit',   'EditUndo,EditRedo,-,EditCut,EditCopy,EditPaste,EditPasteAsNew,EditPasteAsNewLayer,EditDeleteSelection,-,EditSelectAll,EditInvertSelection,EditSelectionFit,EditDeselect');
  AddMenus('MenuSelect', 'EditSelection,FileLoadSelection,FileSaveSelectionAs,-,EditSelectAll,EditInvertSelection,EditSelectionFit,EditDeselect,-,ToolSelectRect,ToolSelectEllipse,ToolSelectPoly,ToolSelectSpline,-,ToolMoveSelection,ToolRotateSelection,SelectionHorizontalFlip,SelectionVerticalFlip,-,ToolSelectPen,ToolMagicWand');
  AddMenus('MenuView',   'ViewGrid,ViewZoomOriginal,ViewZoomIn,ViewZoomOut,ViewZoomFit,-,ViewToolBox,ViewColors,ViewPalette,ViewLayerStack,ViewImageList,ViewStatusBar,-,*,-,ViewDarkTheme,ViewWorkspaceColor,MenuIconSize');
  AddMenus('MenuImage',  'ImageCrop,ImageCropLayer,ImageFlatten,MenuRemoveTransparency,-,ImageNegative,ImageLinearNegative,ImageSwapRedBlue,-,ImageChangeCanvasSize,ImageRepeat,-,ImageResample,ImageSmartZoom3,-,ImageRotateCW,ImageRotateCCW,ImageHorizontalFlip,ImageVerticalFlip');
  AddMenus('MenuRemoveTransparency', 'ImageClearAlpha,ImageFillBackground');
  AddMenus('MenuFilter', 'MenuRadialBlur,FilterBlurMotion,FilterBlurCustom,FilterPixelate,-,FilterSharpen,FilterSmooth,FilterNoise,FilterMedian,FilterClearType,FilterClearTypeInverse,FilterFunction,-,FilterContour,FilterEmboss,FilterPhong,-,FilterSphere,FilterTwirl,FilterCylinder');
  AddMenus('MenuRadialBlur',  'FilterBlurBox,FilterBlurFast,FilterBlurRadial,FilterBlurCorona,FilterBlurDisk');
  AddMenus('MenuColors', 'ColorCurves,ColorPosterize,ColorColorize,ColorShiftColors,FilterComplementaryColor,ColorIntensity,-,ColorLightness,FilterNegative,FilterLinearNegative,FilterNormalize,FilterGrayscale');
  AddMenus('MenuTool',   'ToolHand,ToolHotSpot,ToolColorPicker,-,ToolPen,ToolBrush,ToolEraser,ToolFloodFill,ToolClone,-,ToolRect,ToolEllipse,ToolPolygon,ToolSpline,ToolGradient,ToolPhong,ToolText,-,ToolDeformation,ToolTextureMapping');
  AddMenus('MenuRender', 'RenderPerlinNoise,RenderCyclicPerlinNoise,-,RenderWater,RenderCustomWater,RenderSnowPrint,RenderWood,RenderWoodVertical,RenderMetalFloor,RenderPlastik,RenderStone,RenderRoundStone,RenderMarble,RenderCamouflage,-,RenderClouds,FilterRain');
  AddMenus('MenuHelp',   'HelpIndex,-,HelpAbout');
  for i := 0 to high(FMainMenus) do
    if FMainMenus[i].Count = 0 then FMainMenus[i].visible := false;

  ApplyShortcuts;

  if Assigned(FImageList) then
    FActionList.Images := FImageList;

  tbHeightOrig := DoScaleY(26,OriginalDPI);
  tbHeight := tbHeightOrig;
  for i := 0 to high(FToolbars) do
  with FToolbars[i].tb do
  begin
    Top := 0;
    Left := -Width;
    Color := clBtnFace;
    for j := 0 to ControlCount-1 do
    begin
      if Controls[j] is TToolBar then
      begin
        if assigned(FImageList) then TToolbar(Controls[j]).Images := FImageList;
        TToolbar(Controls[j]).ButtonWidth := TToolbar(Controls[j]).Images.Width+ScaleX(6, 96);
        TToolbar(Controls[j]).ButtonHeight := TToolbar(Controls[j]).Images.Height+ScaleY(6, 96);
      end;
      if Controls[j] is TSpinEdit then
      begin
        if Controls[j].Top + Controls[j].Height+4 > tbHeight then
          tbHeight := Controls[j].Top + Controls[j].Height+4;
      end;
    end;
  end;
  for i := 0 to high(FToolbars) do
  with FToolbars[i].tb do
  begin
    Height := tbHeight;
    for j := 0 to ControlCount-1 do
    begin
      if not (Controls[j] is TSpinEdit) then
        Controls[j].Top := Controls[j].Top + (tbHeight-tbHeightOrig) div 2;
    end;
  end;

  ApplyTheme;
end;

procedure TMainFormMenu.ArrangeToolbars(ClientWidth: integer);
var i,j,k,curx,cury,maxh, w, minNextX, delta: integer; tb: TPanel;
begin
   curx := 0;
   cury := 0;
   maxh := 0;
   for i := 0 to high(FToolbars) do
   begin
     tb := FToolbars[i].tb;

     if not FToolbars[i].fixed then
     begin
       for j := 0 to tb.ControlCount-1 do
       begin
         if not (tb.Controls[j] is TSpinEdit) then
         begin
           tb.Controls[j].Top := 1;
           tb.Controls[j].Height := tb.Height-3;
         end;
         if tb.Controls[j] is TToolBar then
         begin
           minNextX := MaxLongInt;
           for k := 0 to tb.ControlCount-1 do
             if tb.Controls[k].Left > tb.Controls[j].Left then
               minNextX := min(minNextX, tb.Controls[k].Left);
           delta := tb.Controls[j].Left+tb.Controls[j].Width+2-minNextX;
           for k := 0 to tb.ControlCount-1 do
             if tb.Controls[k].Left > tb.Controls[j].Left then
               tb.Controls[k].Left := tb.Controls[k].Left+delta;
         end;
       end;
     end;

     w := 2;
     for j := 0 to tb.ControlCount-1 do
       if tb.Controls[j].Visible then
         w := max(w, tb.Controls[j].Left + tb.Controls[j].Width);
     w += 2;
     tb.Width := w;

     if tb.Visible then
     begin
       if curx+tb.Width > ClientWidth then
       begin
         curx := 0;
         cury += maxh;
         maxh := 0;
       end;
       tb.Left := curx;
       tb.Top := cury;
       inc(curx, tb.Width);
       if tb.Height > maxh then maxh := tb.Height;
     end else
     begin
       //hide fix for Gtk
       tb.Top := -tb.Height;
     end;
   end;
   if curx <> 0 then FToolbarsHeight := cury+maxh else FToolbarsHeight := cury;
   if FToolbarsHeight = 0 then
   begin
     FToolbarBackground.Visible := false;
   end else
   begin
     FToolbarBackground.Top := 0;
     FToolbarBackground.Left := 0;
     FToolbarBackground.width := ClientWidth;
     FToolbarBackground.Height := FToolbarsHeight;
     FToolbarBackground.Visible := true;
   end;
end;

procedure TMainFormMenu.RepaintToolbar;
var i: NativeInt;
begin
  FToolbarBackground.Invalidate;
  for i := 0 to high(FToolbars) do FToolbars[i].tb.Invalidate;
  FToolbarBackground.Update;
  for i := 0 to high(FToolbars) do FToolbars[i].tb.Update;
end;

procedure TMainFormMenu.ApplyShortcuts;
begin
  ActionShortcut('ToolHand','H');
  ActionShortcut('ToolHotSpot','H');
  ActionShortcut('ToolPen','P');
  ActionShortcut('ToolBrush','B');
  ActionShortcut('ToolColorPicker','I');
  ActionShortcut('ToolEraser','E');
  ActionShortcut('ToolRect','U');
  ActionShortcut('ToolEllipse','U');
  ActionShortcut('ToolPolygon','D');
  ActionShortcut('ToolSpline','D');
  ActionShortcut('ToolFloodfill','G');
  ActionShortcut('ToolGradient','G');
  ActionShortcut('ToolPhong','G');
  ActionShortcut('ToolText','T');
  ActionShortcut('ToolSelectRect','M');
  ActionShortcut('ToolSelectEllipse','M');
  ActionShortcut('ToolSelectPoly','A');
  ActionShortcut('ToolSelectSpline','A');
  ActionShortcut('ToolMoveSelection','V');
  ActionShortcut('ToolRotateSelection','V');
  ActionShortcut('ToolSelectPen','O');
  ActionShortcut('ToolMagicWand','W');
  ActionShortcut('ViewZoomIn','+');
  ActionShortcut('ViewZoomOut','-');
end;

end.


unit UToolText;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, UTool, UToolVectorial, LCLType, Graphics, BGRABitmap, BGRABitmapTypes, BGRATextFX,
  BGRAGradients, LCVectorOriginal;

type

  { TToolText }

  TToolText = class(TVectorialTool)
  protected
    FMatrix: TAffineMatrix;
    FPrevShadow: boolean;
    FPrevShadowOffset: TPoint;
    FPrevShadowRadius: single;
    function CreateShape: TVectorShape; override;
    function AlwaysRasterizeShape: boolean; override;
    procedure IncludeShadowBounds(var ARect: TRect);
    function GetCustomShapeBounds(ADestBounds: TRect; AMatrix: TAffineMatrix; ADraft: boolean): TRect; override;
    procedure DrawCustomShape(ADest: TBGRABitmap; AMatrix: TAffineMatrix; ADraft: boolean); override;
    procedure ShapeChange(ASender: TObject; ABounds: TRectF; ADiff: TVectorShapeDiff); override;
    procedure ShapeEditingChange(ASender: TObject); override;
    procedure AssignShapeStyle(AMatrix: TAffineMatrix; AAlwaysFit: boolean); override;
    function SlowShape: boolean; override;
    procedure QuickDefineEnd; override;
    function RoundCoordinate(ptF: TPointF): TPointF; override;
  public
    constructor Create(AManager: TToolManager); override;
    function GetContextualToolbars: TContextualToolbars; override;
    function ToolKeyDown(var key: Word): TRect; override;
    function ToolCommand(ACommand: TToolCommand): boolean; override;
    function ToolProvideCommand(ACommand: TToolCommand): boolean; override;
  end;

implementation

uses LCVectorTextShapes, BGRALayerOriginal, BGRATransform, BGRAGrayscaleMask,
  ugraph, math;

{ TToolText }

function TToolText.CreateShape: TVectorShape;
begin
  result := TTextShape.Create(nil);
end;

function TToolText.AlwaysRasterizeShape: boolean;
begin
  Result:= Manager.TextShadow;
end;

procedure TToolText.IncludeShadowBounds(var ARect: TRect);
var
  shadowRect: TRect;
begin
  if Manager.TextShadow then
  begin
    shadowRect := ARect;
    shadowRect.Inflate(ceil(Manager.TextShadowBlurRadius),ceil(Manager.TextShadowBlurRadius));
    shadowRect.Offset(Manager.TextShadowOffset.X,Manager.TextShadowOffset.Y);
    ARect := RectUnion(ARect, shadowRect);
  end;
end;

function TToolText.GetCustomShapeBounds(ADestBounds: TRect; AMatrix: TAffineMatrix; ADraft: boolean): TRect;
begin
  Result:= inherited GetCustomShapeBounds(ADestBounds, AMatrix, ADraft);
  IncludeShadowBounds(result);
  result.Intersect(ADestBounds);
end;

procedure TToolText.DrawCustomShape(ADest: TBGRABitmap; AMatrix: TAffineMatrix; ADraft: boolean);
var
  temp: TBGRABitmap;
  blur, gray, grayShape: TGrayscaleMask;
  shapeBounds, blurBounds, r, actualShapeBounds: TRect;
begin
  if Manager.TextShadow then
  begin
    shapeBounds := GetCustomShapeBounds(rect(0,0,ADest.Width,ADest.Height),AMatrix,ADraft);
    shapeBounds.Intersect(ADest.ClipRect);
    if (shapeBounds.Width > 0) and (shapeBounds.Height > 0) then
    begin
      temp := TBGRABitmap.Create(shapeBounds.Width,shapeBounds.Height);
      inherited DrawCustomShape(temp, AffineMatrixTranslation(-shapeBounds.Left,-shapeBounds.Top)*AMatrix, ADraft);
      actualShapeBounds := temp.GetImageBounds;
      if not actualShapeBounds.IsEmpty then
      begin
        actualShapeBounds.Offset(shapeBounds.Left,shapeBounds.Top);
        grayShape := TGrayscaleMask.Create;
        grayShape.CopyFrom(temp, cAlpha);

        blurBounds := actualShapeBounds;
        blurBounds.Inflate(ceil(Manager.TextShadowBlurRadius),ceil(Manager.TextShadowBlurRadius));
        blurBounds.Offset(Manager.TextShadowOffset.X,Manager.TextShadowOffset.Y);
        r := ADest.ClipRect;
        r.Inflate(ceil(Manager.TextShadowBlurRadius),ceil(Manager.TextShadowBlurRadius));
        blurBounds.Intersect(r);
        gray := TGrayscaleMask.Create(blurBounds.Width,blurBounds.Height);
        gray.PutImage(shapeBounds.Left-blurBounds.Left+Manager.TextShadowOffset.X,
                      shapeBounds.Top-blurBounds.Top+Manager.TextShadowOffset.Y,grayShape,dmSet);
        grayShape.Free;
        blur := gray.FilterBlurRadial(Manager.TextShadowBlurRadius,Manager.TextShadowBlurRadius, rbFast) as TGrayscaleMask;
        gray.Free;
        ADest.FillMask(blurBounds.Left,blurBounds.Top,blur,BGRABlack,dmDrawWithTransparency);
        blur.Free;
      end;
      ADest.PutImage(shapeBounds.Left,shapeBounds.Top,temp,dmDrawWithTransparency);
      temp.Free;
    end;
    FPrevShadow := true;
    FPrevShadowRadius := Manager.TextShadowBlurRadius;
    FPrevShadowOffset := Manager.TextShadowOffset;
  end else
  begin
    inherited DrawCustomShape(ADest, AMatrix, ADraft);
    FPrevShadow := false;
  end;
end;

procedure TToolText.ShapeChange(ASender: TObject; ABounds: TRectF; ADiff: TVectorShapeDiff);
var
  r: TRect;
  posF: TPointF;
begin
  posF := AffineMatrixInverse(FMatrix)*(FShape as TTextShape).LightPosition;
  Manager.LightPosition := posF;
  with ABounds do r := rect(floor(Left),floor(Top),ceil(Right),ceil(Bottom));
  IncludeShadowBounds(r);
  inherited ShapeChange(ASender, RectF(r.Left,r.Top,r.Right,r.Bottom), ADiff);
end;

procedure TToolText.ShapeEditingChange(ASender: TObject);
begin
  with (FShape as TTextShape) do
    Manager.TextAlign := ParagraphAlignment;
  inherited ShapeEditingChange(ASender);
end;

procedure TToolText.AssignShapeStyle(AMatrix: TAffineMatrix; AAlwaysFit: boolean);
var
  r: TRect;
  toolDest: TBGRABitmap;
  zoom: Single;
  gradBox: TAffineBox;
begin
  FMatrix := AMatrix;
  with TTextShape(FShape) do
  begin
    zoom := (VectLen(AMatrix[1,1],AMatrix[2,1])+VectLen(AMatrix[1,2],AMatrix[2,2]))/2;
    FontEmHeight:= zoom*Manager.TextFontSize*Manager.Image.DPI/72;
    FontName:= Manager.TextFontName;
    FontStyle:= Manager.TextFontStyle;
    gradBox := self.SuggestGradientBox;

    if FSwapColor then
      AssignFill(FShape.PenFill, Manager.BackFill, gradBox, AAlwaysFit)
    else
      AssignFill(FShape.PenFill, Manager.ForeFill, gradBox, AAlwaysFit);

    if Manager.TextOutline and (Manager.TextOutlineWidth>0) and
       (Manager.BackColor.alpha > 0) then
    begin
      if FSwapColor then
        AssignFill(FShape.OutlineFill, Manager.ForeFill, gradBox, AAlwaysFit)
      else
        AssignFill(FShape.OutlineFill, Manager.BackFill, gradBox, AAlwaysFit);
      OutlineWidth := Manager.TextOutlineWidth;
    end
    else
      OutlineFill.Clear;

    LightPosition := AMatrix*Manager.LightPosition;
    AltitudePercent:= Manager.PhongShapeAltitude;
    ParagraphAlignment:= Manager.TextAlign;
    PenPhong := Manager.TextPhong;
  end;
  if (Manager.TextShadow <> FPrevShadow) or
     (Manager.TextShadowBlurRadius <> FPrevShadowRadius) or
     (Manager.TextShadowOffset <> FPrevShadowOffset) then
  begin
    toolDest := GetToolDrawingLayer;
    r:= UpdateShape(toolDest);
    Action.NotifyChange(toolDest, r);
  end;
end;

function TToolText.SlowShape: boolean;
begin
  Result:= true;
end;

procedure TToolText.QuickDefineEnd;
begin
  FShape.Usermode := vsuEditText;
end;

function TToolText.RoundCoordinate(ptF: TPointF): TPointF;
begin
  result := PointF(floor(ptF.x)+0.5,floor(ptF.y)+0.5);
end;

constructor TToolText.Create(AManager: TToolManager);
begin
  inherited Create(AManager);
  FMatrix := AffineMatrixIdentity;
end;

function TToolText.GetContextualToolbars: TContextualToolbars;
begin
  Result:= [ctFill,ctText,ctTextShadow];
  if Manager.TextPhong then include(result, ctAltitude);
end;

function TToolText.ToolKeyDown(var key: Word): TRect;
var
  keyUtf8: TUTF8Char;
  handled: Boolean;
begin
  if Key = VK_SPACE then
  begin
    keyUtf8:= ' ';
    result := ToolKeyPress(keyUtf8);
    Key := 0;
  end else
  if (Key = VK_ESCAPE) and Assigned(FShape) then
  begin
    result := ValidateShape;
    Key := 0;
  end else
  if (Key = VK_RETURN) and Assigned(FShape) then
  begin
    handled := false;
    FShape.KeyDown(FShiftState, skReturn, handled);
    if handled then Key := 0;
  end else
    Result:=inherited ToolKeyDown(key);
end;

function TToolText.ToolCommand(ACommand: TToolCommand): boolean;
begin
  case ACommand of
  tcCopy: Result:= Assigned(FShape) and TTextShape(FShape).CopySelection;
  tcCut: Result:= Assigned(FShape) and TTextShape(FShape).CutSelection;
  tcPaste: Result:= Assigned(FShape) and TTextShape(FShape).PasteSelection;
  tcDelete: Result:= Assigned(FShape) and TTextShape(FShape).DeleteSelection;
  else
    result := inherited ToolCommand(ACommand);
  end;
end;

function TToolText.ToolProvideCommand(ACommand: TToolCommand): boolean;
begin
  case ACommand of
  tcCopy,tcCut,tcDelete: result := Assigned(FShape) and TTextShape(FShape).HasSelection;
  tcPaste: result := Assigned(FShape);
  else
    result := inherited ToolProvideCommand(ACommand);
  end;
end;

initialization

    RegisterTool(ptText, TToolText);

end.


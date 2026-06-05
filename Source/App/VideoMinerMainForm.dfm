object VideoMinerForm: TVideoMinerMainForm
  Left = 0
  Top = 0
  Caption = 'VideoMiner'
  ClientHeight = 545
  ClientWidth = 720
  Color = clBtnFace
  DoubleBuffered = True
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  TextHeight = 13
  object LabelInfo: TLabel
    Left = 16
    Top = 48
    Width = 688
    Height = 72
    AutoSize = False
    Caption = 'No video loaded'
  end
  object ImagePreview: TImage
    Left = 8
    Top = 128
    Width = 688
    Height = 369
    Center = True
    Proportional = True
    Stretch = True
  end
  object ButtonOpen: TButton
    Left = 16
    Top = 16
    Width = 96
    Height = 25
    Caption = 'Open MP4'
    TabOrder = 0
    OnClick = ButtonOpenClick
  end
  object ButtonPlay: TButton
    Left = 120
    Top = 16
    Width = 75
    Height = 25
    Caption = 'Play'
    TabOrder = 1
    OnClick = ButtonPlayClick
  end
  object ButtonStop: TButton
    Left = 201
    Top = 16
    Width = 75
    Height = 25
    Caption = 'Stop'
    TabOrder = 2
    OnClick = ButtonStopClick
  end
  object ButtonOutput: TButton
    Left = 282
    Top = 16
    Width = 96
    Height = 25
    Caption = 'Output MP4'
    TabOrder = 3
    OnClick = ButtonOutputClick
  end
  object TrackBarSeek: TTrackBar
    Left = 8
    Top = 504
    Width = 688
    Height = 33
    Max = 0
    TabOrder = 4
    TickStyle = tsNone
    OnChange = TrackBarSeekChange
  end
  object TimerPlayback: TTimer
    Enabled = False
    Interval = 100
    OnTimer = TimerPlaybackTimer
    Left = 216
    Top = 48
  end
  object OpenDialogVideo: TOpenDialog
    Filter = 
      'MP4 files (*.mp4)|*.mp4|Video files|*.mp4;*.mov;*.mkv;*.avi|All ' +
      'files (*.*)|*.*'
    Options = [ofHideReadOnly, ofFileMustExist, ofEnableSizing]
    Title = 'Open video file'
    Left = 128
    Top = 48
  end
end



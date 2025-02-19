program rgb2sdas;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}{$IFDEF UseCThreads}
  cthreads,
  {$ENDIF}{$ENDIF}
  Classes, SysUtils, strutils, math
  { you can add units after this };

type
  TRSymbol = packed record
    ID: Integer;
    Name: String;
    SymType: Byte;

    No: Integer;
    BankAlias: boolean;
    BankValue: Integer;

    SourceFile, LineNum, SectionID, Value: LongInt;
  end;

  TRPatch = packed record
    SourceFile: LongInt;
    LineNo: LongInt;
    Offset: LongInt;
    PCSectionID: LongInt;
    PCOffset: LongInt;
    PatchType: Byte;
    RPNSize: LongInt;
    RPN: array of Byte;
  end;

  TRSection = packed record
    ID: Integer;
    Name: String;
    Size: LongInt;
    SectType: Byte;
    Org: LongInt;
    Bank: LongInt;
    Align: Byte;
    Ofs: LongInt;

    Data: array of Byte;
    NumberOfPatches: LongInt;
    Patches: array of TRPatch;
  end;

  TRNode = packed record
    ParentID: LongInt;
    ParentLineNo: LongInt;
    NodeType: Byte;

    Name: String;
    Depth: LongInt;
    Iter: array of LongInt;
  end;

  TRObj = packed record
    ID: array[0..3] of AnsiChar;
    RevisionNumber: LongInt;
    NumberOfSymbols: LongInt;
    NumberOfSections: LongInt;
    NumberOfNodes: LongInt;

    Nodes: array of TRNode;
    Symbols: array of TRSymbol;
    Sections: array of TRSection;
  end;

  TRPNTag = (
    rpnPlus,
    rpnMinus,
    rpnTimes,
    rpnDiv,
    rpnMod,
    rpnNegate,
    rpnExponent,
    rpnOr,
    rpnAnd,
    rpnXor,
    rpnComplement,
    rpnBoolAnd,
    rpnBoolOr,
    rpnBoolNeg,
    rpnEqual,
    rpnNotEqual,
    rpnGreater,
    rpnLess,
    rpnGreaterEqual,
    rpnLessEqual,
    rpnShl,
    rpnShr,
    rpnBankSymbol,
    rpnBankSection,
    rpnCurrentBank,
    rpnSizeOfSection,
    rpnStartOfSection,
    rpnHramCheck,
    rpnRstCheck,
    rpnInteger,
    rpnSymbol);

  TRPNNode = record
               case Tag: TRPNTag of
                 rpnBankSymbol: (BankSymbol: Integer);
                 rpnBankSection: (BankSection: ShortString);
                 rpnInteger: (IntValue: Integer);
                 rpnSymbol: (SymbolID: Integer);
                 rpnSizeOfSection: (SizeOfSection: ShortString);
                 rpnStartOfSection: (StartOfSection: ShortString);
             end;
  TRPN = array of TRPNNode;

type 
  TObjFileStream = class(TFileStream)
    function ReadNullTerm: string; virtual;
  end;

function TObjFileStream.ReadNullTerm: string;
var B: Byte;
begin
  Result := '';
  while True do begin
    B := ReadByte;
    if B = 0 then Exit;
    Result += Chr(B);
  end
end;

const
  WRAM0 = 0;
  VRAM = 1;
  ROMX = 2;
  ROM0 = 3;
  HRAM = 4;
  WRAMX = 5;
  SRAM = 6;
  OAM = 7;

const 
  SYM_LOCAL = 0;
  SYM_IMPORT = 1; 
  SYM_EXPORT = 2;

const 
  PATCH_BYTE = 0;
  PATCH_LE_WORD = 1;
  PATCH_LE_LONG = 2;
  PATCH_JR = 3;

procedure Die(const S: String); overload;
begin WriteLn('ERROR: ', S); Halt; end;
procedure Die(const fmt: String; const params: array of const); overload;
begin Die(format(fmt, params)); end;

function ReadObjFile(const afilename: string): TRObj;
const Sign : array[0..3] of AnsiChar = 'RGB9';
var I, J: Integer;
begin
  with TObjFileStream.Create(afilename, fmOpenRead) do try 
    Read(Result, SizeOf(TRObj) - SizeOf(Result.Symbols) - SizeOf(Result.Sections) - SizeOf(Result.Nodes));

    if (not CompareMem(@Result.ID, @Sign, sizeof(Result.ID))) or (not InRange(Result.RevisionNumber, 6, 8)) then
      Die(
        'Unsupported object file version! This version of rgb2sdas supports RGB9, revision 6, 7, or 8 files. The provided file is '+
        Result.ID+', revision '+IntToStr(Result.RevisionNumber)+'.'
      );

    SetLength(Result.Symbols, Result.NumberOfSymbols);
    SetLength(Result.Sections, Result.NumberOfSections);
    SetLength(Result.Nodes, Result.NumberOfNodes);

    for I := Result.NumberOfNodes-1 downto 0 do begin
      Result.Nodes[I] := Default(TRNode);
      with Result.Nodes[I] do begin
        Read(ParentID, SizeOf(ParentID));
        Read(ParentLineNo, SizeOf(ParentLineNo));
        Read(NodeType, SizeOf(NodeType));

        if NodeType <> 0 then
          Name := ReadNullTerm
        else begin
          Read(Depth, SizeOf(Depth));
          SetLength(Iter, Depth);
          Read(Iter[0], Depth*SizeOf(LongInt));
        end;
      end;
    end;

    for I := 0 to Result.NumberOfSymbols-1 do begin
      Result.Symbols[I] := Default(TRSymbol);
      with Result.Symbols[I] do begin
        ID := I;
        Name := ReadNullTerm;
        Read(SymType, SizeOf(SymType));
        if ((SymType and $7F) <> SYM_IMPORT) then begin
          Read(SourceFile, SizeOf(SourceFile));
          Read(LineNum, SizeOf(LineNum));
          Read(SectionID, SizeOf(SectionID));
          Read(Value, SizeOf(Value));
        end;
      end;
    end;

    for I := 0 to Result.NumberOfSections-1 do begin
      Result.Sections[I] := Default(TRSection);
      with Result.Sections[I] do begin
        ID := I;
        Name := ReadNullTerm;
        Read(Size, SizeOf(Size));
        Read(SectType, SizeOf(SectType));
        Read(Org, SizeOf(Org));
        Read(Bank, SizeOf(Bank));
        Read(Align, SizeOf(Align));
        Read(Ofs, SizeOf(Ofs));
        if ((SectType = ROMX) or (SectType = ROM0)) then begin
          SetLength(Data, Size);
          Read(Data[0], Size);
          Read(NumberOfPatches, SizeOf(NumberOfPatches));
          SetLength(Patches, NumberOfPatches);
        end;
      end;

      for J := 0 to Result.Sections[I].NumberOfPatches-1 do begin
        with Result.Sections[I].Patches[J] do begin
          Read(SourceFile, SizeOf(SourceFile));
          Read(LineNo, SizeOf(LineNo));
          Read(Offset, SizeOf(Offset));
          Read(PCSectionID, SizeOf(PCSectionID));
          Read(PCOffset, SizeOf(PCOffset));
          Read(PatchType, SizeOf(PatchType));
          Read(RPNSize, SizeOf(RPNSize));
          SetLength(RPN, RPNSize);
          Read(RPN[0], RPNSize);
        end;
      end;
    end;
  finally free; end;
end;

function RPNToString(const RPN: array of Byte; const Syms: array of TRSymbol): String;
var
  I: Integer;

  function ReadLong: LongWord;
  begin
    Inc(I);
    Result := RPN[I];
    Inc(I);
    Result := (Result shl 8) or RPN[I];
    Inc(I);
    Result := (Result shl 8) or RPN[I];
    Inc(I);
    Result := (Result shl 8) or RPN[I];
    Inc(I);
    Result := SwapEndian(Result);
  end;

  function ReadNullTermRPN: String;
  var
    C: Integer;
  begin
    Result := '';

    C := RPN[I];
    Inc(I);
    while C <> 0 do begin
      Result += Chr(C);

      C := RPN[I];
      Inc(I);
    end;
  end;

begin
  Result := '';

  I := Low(RPN);
  while I <= High(RPN) do begin
    case RPN[I] of
      $00: begin Result += '+ ';   Inc(I); end;
      $01: begin Result += '- ';   Inc(I); end;
      $02: begin Result += '* ';   Inc(I); end;
      $03: begin Result += '/ ';   Inc(I); end;
      $04: begin Result += '% ';   Inc(I); end;
      $05: begin Result += 'neg '; Inc(I); end;
      $06: begin Result += '** ';  Inc(I); end;
      $10: begin Result += '| ';   Inc(I); end;
      $11: begin Result += '& ';   Inc(I); end;
      $12: begin Result += '^ ';   Inc(I); end;
      $13: begin Result += '~ ';   Inc(I); end;
      $21: begin Result += '&& ';  Inc(I); end;
      $22: begin Result += '|| ';  Inc(I); end;
      $23: begin Result += '! ';   Inc(I); end;
      $30: begin Result += '== ';  Inc(I); end;
      $31: begin Result += '!= ';  Inc(I); end;
      $32: begin Result += '> ';   Inc(I); end;
      $33: begin Result += '< ';   Inc(I); end;
      $34: begin Result += '>= ';  Inc(I); end;
      $35: begin Result += '<= ';  Inc(I); end;
      $40: begin Result += '<< ';  Inc(I); end;
      $41: begin Result += '>> ';  Inc(I); end;
      $50: begin Result += '(bank-sym ' + IntToStr(ReadLong)+') '; end;
      $51: begin Result += '(bank-section ' + ReadNullTermRPN+') '; end;
      $52: begin Result += 'current-bank'; Inc(I); end;
      $53: begin Result += '(size-of '+ReadNullTermRPN+') '; end;
      $54: begin Result += '(start-of '+ReadNullTermRPN+') '; end;
      $60: begin Result += 'hram-check';   Inc(I); end;
      $61: begin Result += 'rst-check';    Inc(I); end;
      $80: begin Result += '(int ' + IntToStr(ReadLong)+') '; end;
      $81: begin Result += '(sym ' + Syms[ReadLong].Name+') '; end;
      else Die('Invalid opcode in RPN detected: ', [RPN[I]]);
    end;
  end;
end;

function ParseRPN(const RPN: array of Byte): TRPN;
var
  I: Integer;
  Node: TRPNNode;

  function ReadLong: LongWord;
  begin
    Inc(I);
    Result := RPN[I];
    Inc(I);
    Result := (Result shl 8) or RPN[I];
    Inc(I);
    Result := (Result shl 8) or RPN[I];
    Inc(I);
    Result := (Result shl 8) or RPN[I];
    Inc(I);
    Result := SwapEndian(Result);
  end;

  function ReadNullTermRPN: String;
  var
    C: Integer;
  begin
    Result := '';

    C := RPN[I];
    Inc(I);
    while C <> 0 do begin
      Result += Chr(C);

      C := RPN[I];
      Inc(I);
    end;
  end;

  function nd(Tag: TRPNTag): TRPNNode;
  begin Result.Tag := Tag; end;

  procedure PushRPN(Node: TRPNNode);
  begin
    SetLength(Result, Length(Result)+1);
    Result[High(Result)] := Node;
  end;

begin
  SetLength(Result, 0);
  I := Low(RPN);
  while I <= High(RPN) do begin
    case RPN[I] of
      $00: begin PushRPN(Nd(rpnPlus));         Inc(I); end;
      $01: begin PushRPN(Nd(rpnMinus));        Inc(I); end;
      $02: begin PushRPN(Nd(rpnTimes));        Inc(I); end;
      $03: begin PushRPN(Nd(rpnDiv));          Inc(I); end;
      $04: begin PushRPN(Nd(rpnMod));          Inc(I); end;
      $05: begin PushRPN(Nd(rpnNegate));       Inc(I); end;
      $06: begin PushRPN(Nd(rpnExponent));     Inc(I); end;
      $10: begin PushRPN(Nd(rpnOr));           Inc(I); end;
      $11: begin PushRPN(Nd(rpnAnd));          Inc(I); end;
      $12: begin PushRPN(Nd(rpnXor));          Inc(I); end;
      $13: begin PushRPN(Nd(rpnComplement));   Inc(I); end;
      $21: begin PushRPN(Nd(rpnBoolAnd));      Inc(I); end;
      $22: begin PushRPN(Nd(rpnBoolOr));       Inc(I); end;
      $23: begin PushRPN(Nd(rpnBoolNeg));      Inc(I); end;
      $30: begin PushRPN(Nd(rpnEqual));        Inc(I); end;
      $31: begin PushRPN(Nd(rpnNotEqual));     Inc(I); end;
      $32: begin PushRPN(Nd(rpnGreater));      Inc(I); end;
      $33: begin PushRPN(Nd(rpnLess));         Inc(I); end;
      $34: begin PushRPN(Nd(rpnGreaterEqual)); Inc(I); end;
      $35: begin PushRPN(Nd(rpnLessEqual));    Inc(I); end;
      $40: begin PushRPN(Nd(rpnShl));          Inc(I); end;
      $41: begin PushRPN(Nd(rpnShr));          Inc(I); end;
      $50: begin
             Node.Tag := rpnBankSymbol;
             Node.BankSymbol := ReadLong;
             PushRPN(Node);
           end;
      $51: begin
             Node.Tag := rpnBankSection;
             Node.BankSection := ReadNullTermRPN;
             PushRPN(Node);
           end;
      $52: begin PushRPN(Nd(rpnCurrentBank));  Inc(I); end;
      $53: begin
             Node.Tag := rpnSizeOfSection;
             Node.SizeOfSection := ReadNullTermRPN;
             PushRPN(Node);
           end;
      $54: begin
             Node.Tag := rpnStartOfSection;
             Node.StartOfSection := ReadNullTermRPN;
             PushRPN(Node);
           end;
      $60: begin PushRPN(Nd(rpnHramCheck));    Inc(I); end;
      $61: begin PushRPN(Nd(rpnRstCheck));     Inc(I); end;
      $80: begin
             Node.Tag := rpnInteger;
             Node.IntValue := ReadLong;
             PushRPN(Node);
           end;
      $81: begin
             Node.Tag := rpnSymbol;
             Node.SymbolID := ReadLong;
             PushRPN(Node);
           end;
      else Die('Got malformed RPN!');
    end;
  end;
end;


procedure PrintObjFile(O: TRObj);
var
  Sym: TRSymbol;
  Sect: TRSection;
  Patch: TRPatch;
  SectSize: Integer;
begin
  WriteLn('Symbols:');
  for Sym in O.Symbols do
    Writeln(Format('  %s on %d: type=%d, section=%d, value=%d',
                   [Sym.Name, Sym.LineNum, Sym.SymType, Sym.SectionID, Sym.Value]));
    
  SectSize := 0;
  for Sect in O.Sections do
    if (Sect.Org <> -1) and ((Sect.SectType = ROM0) or (Sect.SectType = ROMX)) then Inc(SectSize, Sect.Size);
  Writeln('Absolute sections: ', SectSize, ' bytes');
  
  SectSize := 0;
  for Sect in O.Sections do
    if (Sect.Org = -1) and ((Sect.SectType = ROM0) or (Sect.SectType = ROMX)) then Inc(SectSize, Sect.Size);
  Writeln('Relative sections: ', SectSize, ' bytes');

  WriteLn('Sections:');
  for Sect in O.Sections do begin
    Writeln(Format('  %s with size %d: offset=%d, patches=%d, bank=%d',
                   [Sect.Name, Sect.Size, Sect.Org, Sect.NumberOfPatches, Sect.Bank]));

    for Patch in Sect.Patches do 
      Writeln(Format('    %s: %d ; %s', [Patch.SourceFile, Patch.PatchType, RPNToString(Patch.RPN, O.Symbols)]));
  end;
end;

function FindPatch(const Section: TRSection; Index: Integer; out Patch: TRPatch): Boolean;
var I: Integer;
begin
  for I := Low(Section.Patches) to High(Section.Patches) do
    if Section.Patches[I].Offset = Index then begin
      Patch := Section.Patches[I];
      Exit(True);
    end;
  Result := False;
end;

function FindSection (const Obj: TRObj; SecionID: Integer; out Section: TRSection): Boolean;
var I: Integer;
begin
  with Obj do
    for I := Low(Sections) to High(Sections) do with Sections[I] do
      if ID = SecionID then begin
        Section := Sections[I];
        Exit(True);
      end;
  Result := False;
end;


var
  RObj: TRObj;

  Symbol: TRSymbol;
  Section: TRSection;
  Patch: TRPatch;

  F: Text;

  ValueToWrite: Word;
  RPN: TRPN;
  I: Word;
  Sct: Word;
  WritePos: Word;
  Idx: Integer;
  CODESEG: string;
  DefaultBank: Integer = 0;
  sourcename, tmp: string;

  old_sym, new_sym: string;

  verbose: boolean = false;

  export_all: boolean = false;

begin
  if (ParamCount() < 1) then begin
    Writeln('Usage: rgb2sdas [-c<code_section>] [-v] [-e] [-r<symbol1>=<symbol2>] [-b<default_bank>] <object_name>');
    Halt;
  end;

  sourcename:= ParamStr(ParamCount());
  if not FileExists(sourcename) then Die('File not found: %s', [sourcename]);

  old_sym:= ''; new_sym:= '';

  CODESEG:= '_CODE';
  for I:= 1 to ParamCount() - 1 do begin
    tmp:= ParamStr(i);
    if (CompareText(tmp, '-v') = 0) then
      verbose:= true
    else if (CompareText(copy(tmp, 1, 2), '-e') = 0) then
      export_all:= true
    else if (CompareText(copy(tmp, 1, 2), '-c') = 0) then begin
      CODESEG:= copy(tmp, 3, length(tmp));
      if length(CODESEG) = 0 then CODESEG:= '_CODE';
      if verbose then writeln('Using CODESEG: ', CODESEG);
    end else if (CompareText(copy(tmp, 1, 2), '-b') = 0) then begin
      DefaultBank:= StrToIntDef(copy(tmp, 3, length(tmp)), DefaultBank);
      if verbose then writeln('Using DefaultBank: ', DefaultBank);
    end else if (CompareText(copy(tmp, 1, 2), '-r') = 0) then begin
      tmp:= copy(tmp, 3, length(tmp));
      Idx:= pos('=', tmp);
      if (idx > 0) then begin
        old_sym:= copy(tmp, 1, idx - 1);
        new_sym:= copy(tmp, idx + 1, length(tmp));
      end;
    end;
  end;

  RObj := ReadObjFile(sourcename);
  if verbose then PrintObjFile(RObj);

  Assign(F, sourcename + '.o');
  Rewrite(F);
  try
    Idx:= 0;
    // pass 1: all imports first
    for I:= Low(RObj.Symbols) to High(RObj.Symbols) do with RObj.Symbols[I] do begin
      case (SymType and $7f) of
        SYM_IMPORT : begin
                       No:= Idx;
                       Inc(Idx);
                     end;
        SYM_EXPORT : begin
                       No:= -1;
                       if FindSection(RObj, SectionID, Section) and (Section.SectType = ROMX) then begin
                         BankAlias:= (max(DefaultBank, Section.Bank) > 0);
                         BankValue:= max(DefaultBank, Section.Bank);
                         if BankAlias then Inc(Idx);
                       end;
                     end;
        else         No:= -1;
      end;
    end;
    // pass 2: all other (export local only when forced)
    for I:= Low(RObj.Symbols) to High(RObj.Symbols) do with RObj.Symbols[I] do begin
      case (SymType and $7f) of
        SYM_LOCAL  : if export_all then begin
                       No:= Idx;
                       Inc(Idx);
                     end;
        SYM_IMPORT : ;
        SYM_EXPORT : begin
                       // rename exported symbol if requested
                       if (length(old_sym) > 0) and (Name = old_sym) then Name:= new_sym;
                       No:= Idx;
                       Inc(Idx);
                     end;
        else         Die('Unsupported symbol type: %d', [SymType and $7f]);
      end;
    end;

    // output object header
    Writeln(F, 'XL3');
    Writeln(F, Format('H %x areas %x global symbols', [RObj.NumberOfSections, idx]));
    Writeln(F, Format('M %s', [StringReplace(ExtractFileName(sourcename), '.', '_', [rfReplaceAll])]));
    Writeln(F, 'O -mgbz80');

    // output all imported symbols
    for I:= Low(RObj.Symbols) to High(RObj.Symbols) do
      with RObj.Symbols[I] do
        if (SymType = SYM_IMPORT) then
          Writeln(F, Format('S %s Ref%.6x', [StringReplace(Name, '.', '____', [rfReplaceAll]), 0]))
        else if ((SymType = SYM_EXPORT) and BankAlias) then
          Writeln(F, Format('S b%s Def%.6x', [StringReplace(Name, '.', '____', [rfReplaceAll]), BankValue]));

    // output all sections and other symbols
    for Section in RObj.Sections do begin
      if Section.Org = -1 then
        case Section.SectType of
          ROM0: Writeln(F, Format('A %s size %x flags 0 addr 0', [CODESEG, Section.Size]));
          ROMX: if (DefaultBank = 0) then Writeln(F, Format('A %s size %x flags 0 addr 0', [CODESEG, Section.Size]))
                                     else Writeln(F, Format('A _CODE_%d size %x flags 0 addr 0', [max(DefaultBank, Section.Bank), Section.Size]));
          else  Writeln(F, Format('A _DATA size %x flags 0 addr 0', [Section.Size]));
        end
      else Die('Absolute sections currently unsupported: %s', [Section.Name]);

      for Symbol in RObj.Symbols do
        if Symbol.SectionID = Section.ID then
          if (Symbol.SymType <> SYM_IMPORT) and (Symbol.No >= 0) then
            Writeln(F, Format('S %s Def%.6x', [StringReplace(Symbol.Name, '.', '____', [rfReplaceAll]), Symbol.Value]));
    end;

    // convert object itself
    for Sct := Low(RObj.Sections) to High(RObj.Sections) do begin
      Section := RObj.Sections[Sct];

      if (Section.SectType <> ROMX) and (Section.SectType <> ROM0) then Continue;
      if Length(Section.Data) <= 0 then Continue;

      I := Low(Section.Data);
      while I <= High(Section.Data) do begin
        WritePos := I;
        if (Section.Org <> -1) then Inc(WritePos, Section.Org);

        if FindPatch(Section, I, Patch) then begin
          RPN := ParseRPN(Patch.RPN);
          case Patch.PatchType of
            PATCH_BYTE    : begin
                              if ((Length(RPN) = 3) and
                                 ((RPN[1].Tag <> rpnInteger) or
                                  (RPN[2].Tag <> rpnAnd)))
                                 or
                                 ((Length(RPN) = 5) and
                                 ((RPN[1].Tag <> rpnInteger) or
                                  (RPN[2].Tag <> rpnShr) or
                                  (RPN[3].Tag <> rpnInteger) or
                                  (RPN[4].Tag <> rpnAnd)))
                                 or (not (Length(RPN) in [3, 5]))
                                 then
                                  Die('Unsupported RPN expression in byte patch');

                              Symbol := RObj.Symbols[RPN[0].SymbolID];
                              if Length(RPN) = 3 then begin // LSB
                                Writeln(F, Format('T %.2x %.2x 00 %.2x %.2x 00', [lo(WritePos), hi(WritePos), lo(Symbol.Value), hi(Symbol.Value)]));
                                Writeln(F, Format('R 00 00 %.2x %.2x 09 03 %.2x %.2x', [lo(Sct), hi(Sct), lo(Symbol.SectionID), hi(Symbol.SectionID)]));
                              end
                              else if Length(RPN) = 5 then begin // MSB
                                Writeln(F, Format('T %.2x %.2x 00 %.2x %.2x 00', [lo(WritePos), hi(WritePos), lo(Symbol.Value), hi(Symbol.Value)]));
                                Writeln(F, Format('R 00 00 %.2x %.2x 89 03 %.2x %.2x', [lo(Sct), hi(Sct), lo(Symbol.SectionID), hi(Symbol.SectionID)]));
                              end;
                              Inc(I);
                            end;
            PATCH_LE_WORD : begin
                              Symbol := RObj.Symbols[RPN[0].SymbolID];
                              ValueToWrite := Symbol.Value;

                              if ((Length(RPN) = 3) and
                                 ((RPN[1].Tag <> rpnInteger) or
                                  (RPN[2].Tag <> rpnPlus)))
                                 or (not (Length(RPN) in [1, 3]))
                              then
                               Die('Unsupported RPN expression in word patch');

                              if RPN[High(RPN)].Tag = rpnPlus then
                                Inc(ValueToWrite, RPN[1].IntValue);

                              if (Symbol.SymType = SYM_IMPORT) then begin
                                  if (Symbol.No < 0) then Die('Trying to reference eliminated symbol');
                                  Writeln(F, Format('T %.2x %.2x 00 %.2x %.2x', [lo(WritePos), hi(WritePos), lo(ValueToWrite), hi(ValueToWrite)]));
                                  Writeln(F, Format('R 00 00 %.2x %.2x 02 03 %.2x %.2x', [lo(Sct), hi(Sct), lo(Symbol.No), hi(Symbol.No)]));
                              end else begin
                                  Writeln(F, Format('T %.2x %.2x 00 %.2x %.2x', [lo(WritePos), hi(WritePos), lo(ValueToWrite), hi(ValueToWrite)]));
                                  Writeln(F, Format('R 00 00 %.2x %.2x 00 03 %.2x %.2x', [lo(Sct), hi(Sct), lo(Symbol.SectionID), hi(Symbol.SectionID)]));
                              end;
                              Inc(I, 2);
                            end;
            PATCH_JR      : begin
                              if Length(RPN) <> 1 then Die('Unsupported RPN expression in JR patch');
                              Symbol := RObj.Symbols[RPN[0].SymbolID];
                              Writeln(F, Format('T %.2x %.2x 00 %.2x', [lo(WritePos), hi(WritePos), Byte(Symbol.Value - I - 1)]));
                              Writeln(F, Format('R 00 00 %.2x %.2x', [lo(Sct), hi(Sct)]));
                              Inc(I);
                            end
            else            Die('Unsupported patch type: %d', [Patch.PatchType]);
          end;
        end else begin
          Writeln(F, Format('T %.2x %.2x 00 %.2x', [lo(WritePos), hi(WritePos), Section.Data[I]]));
          Writeln(F, Format('R 00 00 %.2x %.2x', [lo(Sct), hi(Sct)]));
          Inc(I);
        end;
      end;
    end;

    Writeln('rgb2sdas converting ',sourcename,' --> ',sourcename,'.o result: success!');
  finally Close(F); end;
end.



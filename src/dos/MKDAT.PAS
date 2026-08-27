{ ===========================================================================
  MKDAT -- build NEUROSIS.DAT from a manifest, and emit the offsets as Pascal
  constants.

  Psycho Neurosis ships one 1,718,189-byte data blob with NO DIRECTORY IN IT.
  Every part Assigns it, Seeks to an absolute offset compiled into the code and
  BlockReads a fixed number of bytes. So the blob's structure exists in exactly
  two places: the Seek constants in the seven parts, and nothing else.

  That is workable for reading a blob somebody else built and hopeless for
  building one. Move any file and every offset after it is wrong, in seven
  programs, silently -- the reads still succeed, they just return the wrong
  bytes. This program removes the hand arithmetic:

      MKDAT reads the manifest, concatenates the files in the order given,
      and writes the offset and length of each one out as a CONSTANT.

  The parts then Seek to DAT_P1_INTROSCR instead of $02AEE0, and the offset is
  a consequence of the manifest rather than a number somebody maintains.

  THE CONSTANTS ARE UNTYPED, AND THAT IS THE WHOLE REASON THIS IS SAFE. A
  Turbo Pascal untyped constant is a compile-time value: it is folded into the
  instruction stream at the point of use and occupies no storage. `Seek(F,
  DAT_P1_INTROSCR)` and `Seek(F, $02AEE0)` compile to the same bytes. A TYPED
  constant -- `DAT_P1_INTROSCR : LongInt = $02AEE0` -- would allocate four
  initialised bytes in DGROUP instead, moving every variable after it and
  changing the data image of every part that included the file. This program
  must never emit a type, and the generated header says so where somebody
  editing it would look.

  USAGE

      MKDAT <manifest> [<blob>] [<include>] [<reference>]

      manifest    the ordered list of files. Paths in it are relative to the
                  MANIFEST'S OWN directory, so the manifest and the PARTnnn
                  directories travel together and nothing depends on the
                  current drive.
      blob        output, default NEUROSIS.DAT
      include     output, default DATOFS.INC
      reference   optional. An existing blob to compare the new one against,
                  byte for byte. Given one, MKDAT reports IDENTICAL or the
                  offset of the first difference -- which is the check that
                  matters, because a manifest in the wrong order produces a
                  blob of exactly the right length that every part misreads.

  MANIFEST FORMAT. One entry per line, `<constant> <file>`, whitespace
  separated. Blank lines and lines beginning with `;` are ignored. The order of
  the lines IS the order of the blob.

  THE OFFSETS ARE DELIBERATELY NOT IN THE MANIFEST. They are a consequence of
  the order and the file lengths, so putting them there would be a second copy
  of a derived fact -- and a second copy is a thing that can disagree. MKDAT
  computes them.

  Nothing here is part of the demo. It builds one of its inputs.
  =========================================================================== }

program MkDat;

{$I-}   { I/O errors are handled here, not by the runtime. Every file operation
          below is followed by a check, because "the manifest named a file that
          is not there" has to name the file rather than halt with a code. }
{$S-}

const
  Version   = 'MKDAT 1.0';

  { 16K, and the reason is the 64K segment. The largest single entry in the
    blob is 64,000 bytes and the largest region 269,180, so nothing here can
    be read in one gulp anyway; streaming through a fixed buffer costs one
    loop and works whatever the manifest holds. }
  BufSize   = 16384;

  DefBlob   = 'NEUROSIS.DAT';
  DefInc    = 'DATOFS.INC';

  MaxLine   = 255;

  { The column the `=` sits in. The longest constant a manifest can
    produce here is DAT_Pn_ + eight characters of 8.3 stem = 15, and the
    length line adds _LEN, so 20 clears both with a space to spare. }
  NameCol   = 20;
  Comment   = ';';

type
  TPath = string[79];

var
  Buf      : array[1..BufSize] of Byte;
  Cmp      : array[1..BufSize] of Byte;
  Man      : Text;
  IncFile  : Text;
  Blob     : file;
  Base     : TPath;              { the manifest's directory, paths hang off it }
  ManName  : TPath;
  BlobName : TPath;
  IncName  : TPath;
  RefName  : TPath;
  Offset   : LongInt;            { where the NEXT file will start }
  Count    : Integer;            { entries written }
  Failed   : Boolean;

{ ---------------------------------------------------------------------------
  Report and give up. Every failure here is a manifest or a missing file, so
  the message names the thing rather than the error number.
  --------------------------------------------------------------------------- }
procedure Fail(const Msg, What : string);
begin
  WriteLn;
  WriteLn('MKDAT: ', Msg, ': ', What);
  Failed := True;
end;

{ ---------------------------------------------------------------------------
  The directory part of a path, including its trailing separator. DOS has two
  of them -- the backslash and the drive colon -- and a path may have neither,
  in which case the manifest sits in the current directory and Base is empty.
  --------------------------------------------------------------------------- }
function DirOf(const P : TPath) : TPath;
var
  I : Integer;
begin
  for I := Length(P) downto 1 do
    if (P[I] = '\') or (P[I] = ':') then
    begin
      DirOf := Copy(P, 1, I);
      Exit;
    end;
  DirOf := '';
end;

{ Uppercase hex, fixed width, which is how every offset in the reconstruction's
  sources is written. Six digits covers the blob and lines the column up. }
function Hex6(V : LongInt) : string;
const
  Digits : array[0..15] of Char = '0123456789ABCDEF';
var
  S : string[6];
  I : Integer;
begin
  S := '000000';
  for I := 6 downto 1 do
  begin
    S[I] := Digits[V and $F];
    V := V shr 4;
  end;
  Hex6 := S;
end;

{ The file part of a path, which is the opposite end from DirOf. }
function NameOf(const P : TPath) : TPath;
begin
  NameOf := Copy(P, Length(DirOf(P)) + 1, 79);
end;

{ A name padded to a fixed column, so the constants line up whatever they are
  called. Longer than the column simply overflows it -- an ugly line beats a
  truncated identifier. }
function Pad(const S : string; W : Integer) : string;
var
  R : string;
begin
  R := S;
  while Length(R) < W do R := R + ' ';
  Pad := R;
end;

{ ---------------------------------------------------------------------------
  Split one manifest line into its two fields. Returns False for a line with
  nothing on it -- blank or a comment -- which the caller skips.
  --------------------------------------------------------------------------- }
function Split(const Line : string; var Konst, FileName : TPath) : Boolean;
var
  I, N : Integer;
begin
  Split := False;
  Konst := '';
  FileName := '';
  I := 1;
  N := Length(Line);
  while (I <= N) and (Line[I] <= ' ') do Inc(I);
  if (I > N) or (Line[I] = Comment) then Exit;
  while (I <= N) and (Line[I] > ' ') do
  begin
    Konst := Konst + Line[I];
    Inc(I);
  end;
  while (I <= N) and (Line[I] <= ' ') do Inc(I);
  while (I <= N) and (Line[I] > ' ') do
  begin
    FileName := FileName + Line[I];
    Inc(I);
  end;
  Split := (Length(Konst) > 0) and (Length(FileName) > 0);
end;

{ ---------------------------------------------------------------------------
  Append one file to the blob and emit its two constants. The length is read
  off the FILE rather than declared anywhere, which is the point: the manifest
  says what and in what order, the files say how big, and the offsets follow.
  --------------------------------------------------------------------------- }
procedure Append(const Konst, Rel : TPath);
var
  F    : file;
  Got  : Word;
  Size : LongInt;
begin
  Assign(F, Base + Rel);
  Reset(F, 1);
  if IOResult <> 0 then
  begin
    Fail('the manifest names a file that is not there', Base + Rel);
    Exit;
  end;
  Size := FileSize(F);

  repeat
    BlockRead(F, Buf, BufSize, Got);
    if IOResult <> 0 then
    begin
      Fail('cannot read', Base + Rel);
      Close(F);
      Exit;
    end;
    if Got > 0 then
    begin
      BlockWrite(Blob, Buf, Got);
      if IOResult <> 0 then
      begin
        Fail('cannot write the blob at ' + Hex6(Offset), BlobName);
        Close(F);
        Exit;
      end;
    end;
  until Got < BufSize;
  Close(F);

  { Two constants, both UNTYPED -- see the header. The offset in hex because
    that is how the sources being replaced spell it; the length in decimal
    because that is how their BlockRead calls spell it.

    ONE PAD WIDTH FOR BOTH LINES, computed from the name that is written, not
    from Konst. The first version padded the offset line from Length(Konst) and
    the length line from Length(Konst) again -- which lines the two columns up
    only while the name is short, and the longest name here is fifteen
    characters where the length line adds four more. Two columns that agree on
    the short cases and part company on the long ones is worse than either. }
  Write(IncFile, '  ', Pad(Konst, NameCol), '= $', Hex6(Offset), ';');
  WriteLn(IncFile);
  Write(IncFile, '  ', Pad(Konst + '_LEN', NameCol), '= ', Size, ';');
  WriteLn(IncFile);

  Offset := Offset + Size;
  Inc(Count);
end;

{ ---------------------------------------------------------------------------
  Compare the blob just built against a reference, byte for byte. A manifest
  in the wrong order yields a blob of exactly the right LENGTH, so length is
  not evidence and this is.
  --------------------------------------------------------------------------- }
procedure Compare(const RefFile : TPath);
var
  A, B     : file;
  GotA, GotB : Word;
  At       : LongInt;
  I        : Integer;
begin
  Assign(A, BlobName);
  Reset(A, 1);
  if IOResult <> 0 then
  begin
    Fail('cannot reopen the blob to compare it', BlobName);
    Exit;
  end;
  Assign(B, RefFile);
  Reset(B, 1);
  if IOResult <> 0 then
  begin
    Close(A);
    Fail('no reference to compare against', RefFile);
    Exit;
  end;
  if FileSize(A) <> FileSize(B) then
  begin
    WriteLn('  DIFFERS: ', FileSize(A), ' bytes against ', FileSize(B));
    Close(A);
    Close(B);
    Failed := True;
    Exit;
  end;
  At := 0;
  repeat
    BlockRead(A, Buf, BufSize, GotA);
    BlockRead(B, Cmp, BufSize, GotB);
    for I := 1 to GotA do
      if Buf[I] <> Cmp[I] then
      begin
        WriteLn('  DIFFERS: first at $', Hex6(At + I - 1),
                ' -- built $', Hex6(Buf[I]), ', reference $', Hex6(Cmp[I]));
        Close(A);
        Close(B);
        Failed := True;
        Exit;
      end;
    At := At + GotA;
  until GotA < BufSize;
  Close(A);
  Close(B);
  WriteLn('  IDENTICAL to ', RefFile, ', all ', At, ' bytes.');
end;

var
  Line  : string;
  Konst : TPath;
  Rel   : TPath;
  Lines : LongInt;

begin
  WriteLn(Version, ' -- build NEUROSIS.DAT from a manifest');
  Failed := False;

  if ParamCount < 1 then
  begin
    WriteLn;
    WriteLn('usage: MKDAT <manifest> [<blob>] [<include>] [<reference>]');
    WriteLn;
    WriteLn('  Concatenates the files the manifest names, in its order, and');
    WriteLn('  writes each one''s offset and length as an untyped constant.');
    WriteLn('  Given a reference blob, compares byte for byte afterwards.');
    Halt(1);
  end;

  ManName  := ParamStr(1);
  if ParamCount >= 2 then BlobName := ParamStr(2) else BlobName := DefBlob;
  if ParamCount >= 3 then IncName  := ParamStr(3) else IncName  := DefInc;
  if ParamCount >= 4 then RefName  := ParamStr(4) else RefName  := '';
  Base := DirOf(ManName);

  Assign(Man, ManName);
  Reset(Man);
  if IOResult <> 0 then
  begin
    Fail('cannot open the manifest', ManName);
    Halt(2);
  end;

  Assign(Blob, BlobName);
  Rewrite(Blob, 1);
  if IOResult <> 0 then
  begin
    Close(Man);
    Fail('cannot create', BlobName);
    Halt(2);
  end;

  Assign(IncFile, IncName);
  Rewrite(IncFile);
  if IOResult <> 0 then
  begin
    Close(Man);
    Close(Blob);
    Fail('cannot create', IncName);
    Halt(2);
  end;

  { The header earns its keep: the first thing anybody does with a generated
    file is edit it, and the second is wonder why their edit vanished. }
  WriteLn(IncFile, '{ GENERATED BY ', Version, ' -- DO NOT EDIT.');
  WriteLn(IncFile, '');
  WriteLn(IncFile, '  Offsets and lengths of every file in NEUROSIS.DAT, from');
  { The manifest's BASE NAME, not the path it was invoked with. A generated
    file that records where it was generated FROM is a generated file that
    differs between two correct runs -- one path under DOSBox, another from
    the host mirror -- and then it churns in git every time either runs. }
  WriteLn(IncFile, '  ', NameOf(ManName), '. Rebuild both together: an offset');
  WriteLn(IncFile, '  here that does not match the blob is a part reading the');
  WriteLn(IncFile, '  wrong bytes, and it will not announce itself.');
  WriteLn(IncFile, '');
  WriteLn(IncFile, '  EVERY CONSTANT HERE IS UNTYPED, ON PURPOSE. An untyped');
  WriteLn(IncFile, '  constant is a compile-time value folded into the code at');
  WriteLn(IncFile, '  the point of use, so it costs no storage and this file can');
  WriteLn(IncFile, '  be included by a unit that uses none of it. Giving one a');
  WriteLn(IncFile, '  type -- `X : LongInt = $02AEE0` -- would allocate four');
  WriteLn(IncFile, '  initialised bytes in DGROUP instead, move every variable');
  WriteLn(IncFile, '  after it and change the data image of every part that');
  WriteLn(IncFile, '  included this. Do not add a type. }');
  WriteLn(IncFile, '');
  WriteLn(IncFile, 'const');

  Offset := 0;
  Count  := 0;
  Lines  := 0;
  while not Eof(Man) and not Failed do
  begin
    ReadLn(Man, Line);
    Inc(Lines);
    if IOResult <> 0 then
    begin
      Fail('cannot read the manifest', ManName);
      Break;
    end;
    if Split(Line, Konst, Rel) then
      Append(Konst, Rel);
  end;
  Close(Man);
  Close(Blob);

  WriteLn(IncFile, '');
  WriteLn(IncFile, '  { ', Count, ' files, ', Offset, ' bytes. }');
  Close(IncFile);

  if Failed then
  begin
    WriteLn;
    WriteLn('MKDAT: nothing was built. ', BlobName, ' and ', IncName,
            ' are incomplete.');
    Halt(3);
  end;

  WriteLn('  manifest  ', ManName, ' (', Lines, ' lines)');
  WriteLn('  blob      ', BlobName, ' -- ', Count, ' files, ', Offset, ' bytes');
  WriteLn('  include   ', IncName, ' -- ', Count * 2, ' constants');

  if RefName <> '' then
    Compare(RefName);

  if Failed then Halt(3);
end.

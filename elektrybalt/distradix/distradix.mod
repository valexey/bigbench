MODULE distradix;

IMPORT SYSTEM, cio;
FROM SYSTEM IMPORT ADDRESS, ADR;
FROM cio IMPORT open64, close, read, write, lseek64, sprintf;

TYPE File = cio.FDesc;

CONST
    ibLen = 65536;
    wbLen = 256*ibLen;
    qslim = wbLen DIV 2; (* <= wbLen *)

VAR
    input, output: File;
    partf: ARRAY [0..255] OF File;
    ptcnt: ARRAY [0..255] OF CARDINAL;
    iobuf: ARRAY [0..ibLen-1] OF CARDINAL;
    wkbuf: ARRAY [0..wbLen-1] OF CARDINAL;

(* *)
PROCEDURE Open(name: ARRAY OF CHAR): File;
BEGIN
  RETURN open64(name, cio.O_RDONLY, 0);
END Open;

PROCEDURE Create(name: ARRAY OF CHAR): File;
BEGIN
  RETURN open64(name, cio.O_RDWR + cio.O_CREAT + cio.O_TRUNC, 666B);
END Create;

PROCEDURE  Rewind(fd: File);
BEGIN
  lseek64(fd, 0, cio.SEEK_SET);
END Rewind;
(* *)



PROCEDURE OpenParts;
VAR i : INTEGER; name: ARRAY [0..16] OF CHAR;
BEGIN
  FOR i := 0 TO 255 DO
    sprintf(name, "run-%2.2X", i);
    partf[i] := Create(name);
  END;
END OpenParts;

PROCEDURE Distribute;
VAR n, i, k, len : INTEGER;
    pos: ARRAY [0..255] OF INTEGER;
BEGIN
  input := Open("input");
  FOR k := 0 TO 255 DO ptcnt[k] := 0  END;
  FOR k := 0 TO 255 DO pos[k]:= ibLen*k END;
  n := read(input, ADR(iobuf), SIZE(iobuf)) DIV 4;
  WHILE n > 0 DO
    FOR i := 0 TO n-1 DO
      k := iobuf[i] DIV wbLen MOD 256;
      wkbuf[pos[k]] := iobuf[i];
      INC(pos[k]);
      IF pos[k] = ibLen*(k+1)  THEN
        write(partf[k], ADR(wkbuf[ibLen*k]), 4*ibLen);
        pos[k]:= ibLen*k;
        INC(ptcnt[k], ibLen);
      END;
    END;
    n := read(input, ADR(iobuf), SIZE(iobuf)) DIV 4;
  END;
  FOR k := 0 TO 255 DO
    len := pos[k] - ibLen*k;
    IF len > 0  THEN
      write(partf[k], ADR(wkbuf[ibLen*k]), 4*len);
      INC(ptcnt[k], len);
    END;
  END;
  close(input);
END Distribute;

  PROCEDURE rxSort(l, r: INTEGER);
  VAR k: CARDINAL;
      i, s, t: INTEGER;
      pos0, pos1 : ARRAY [0..4095] OF INTEGER;
  BEGIN
    FOR k := 0 TO 4095 DO pos0[k] := 0 END;
    FOR k := 0 TO 4095 DO pos1[k] := 0 END;

    FOR i := l TO r DO
      INC(pos0[wkbuf[i] MOD 4096]);
      INC(pos1[wkbuf[i] DIV 4096 MOD 4096]);
    END;
    s := l; FOR k := 0 TO 4095 DO t := s + pos0[k]; pos0[k] := s; s := t; END;
    s := l; FOR k := 0 TO 4095 DO t := s + pos1[k]; pos1[k] := s; s := t; END;

    FOR i := l TO r DO
     k:= wkbuf[i] MOD 4096;
     wkbuf[qslim + pos0[k]] := wkbuf[i];
     INC(pos0[k])
    END;
    FOR i := l TO r DO
      k:= wkbuf[qslim + i] DIV 4096 MOD 4096;
      wkbuf[pos1[k]] := wkbuf[qslim + i];
      INC(pos1[k])
    END;
  END  rxSort;

PROCEDURE countSort(k: INTEGER);
VAR n, i, len, outpos: INTEGER; x: CARDINAL;
BEGIN
  FOR i := 0 TO wbLen-1 DO wkbuf[i] := 0 END;
  n := read(partf[k], ADR(iobuf), SIZE(iobuf)) DIV 4;
  WHILE n > 0 DO
    FOR i := 0 TO n-1 DO INC(wkbuf[iobuf[i] MOD wbLen]) END;
    n := read(partf[k], ADR(iobuf), SIZE(iobuf)) DIV 4;
  END;
  outpos := 0;
  FOR i := 0 TO wbLen-1 DO
    len := wkbuf[i];
    IF len = 0 THEN
       (* skip *)
    ELSIF len + outpos < ibLen THEN
      x := k * wbLen + i;
      WHILE len > 0  DO
        iobuf[outpos] := x;
        INC(outpos);
        DEC(len);
      END;
    ELSE
      write(output, ADR(iobuf), outpos*4);
      outpos := 0;
      x := k * wbLen + i;
      IF len < ibLen THEN
        WHILE len > 0  DO
          iobuf[outpos] := x;
          INC(outpos);
          DEC(len);
        END;
      ELSE
        FOR outpos := 0 TO ibLen-1 DO iobuf[outpos] := x END;
        WHILE len >= ibLen  DO
          write(output, ADR(iobuf), ibLen*4);
          DEC(len, ibLen);
        END;
        outpos := len;
      END;
    END;
  END;
  IF outpos > 0 THEN write(output, ADR(iobuf), outpos*4) END;
END countSort;

PROCEDURE Collect;
VAR k, n: INTEGER;
BEGIN
  output := Create("output");
  FOR k := 0 TO 255 DO
    IF ptcnt[k] = 0 THEN
      close(partf[k]);
    ELSIF ptcnt[k] < qslim THEN
      Rewind(partf[k]);
      n := read(partf[k], ADR(wkbuf), 4*ptcnt[k]) DIV 4;
      rxSort(0, n-1);
      write(output, ADR(wkbuf), 4*n);
      close(partf[k]);
    ELSE
      Rewind(partf[k]);
      countSort(k);
      close(partf[k]);
    END;
  END;
  close(output);
END Collect;

BEGIN
  OpenParts;
  Distribute;
  Collect;
END distradix.


MODULE sort;

IMPORT ChanConsts, IOChan, RndFile;
IMPORT SYSTEM, Strings, WholeStr;
FROM Storage IMPORT ALLOCATE;

CONST ibLen = 25*1024*1024;
      obLen = 1024;
      rbLen = 1024;
      runLimit = 300; 

TYPE  Key = CARDINAL;

VAR 
    inbuf:  ARRAY [1..ibLen] OF Key; 

VAR 
    output: IOChan.ChanId;
    outPtr: INTEGER;
    outBuf: ARRAY [1..obLen] OF Key; 

  PROCEDURE OpenOut;
  VAR res  : ChanConsts.OpenResults;
  BEGIN
    RndFile.OpenClean(output, 'output', RndFile.old+RndFile.raw, res);
    outPtr := 0;
  END OpenOut;

  PROCEDURE FlushOut;
  BEGIN
    IOChan.RawWrite(output, SYSTEM.ADR(outBuf), outPtr*SIZE(Key));
    outPtr := 0;
  END FlushOut;

  PROCEDURE PutOut(x : Key);
  BEGIN
    INC(outPtr);
    outBuf[outPtr] := x;
    IF outPtr = obLen THEN FlushOut END;
  END PutOut;

  PROCEDURE CloseOut;
  BEGIN
    IF outPtr > 0 THEN FlushOut END;
    RndFile.Close(output);
    outPtr := 0;
  END CloseOut;

TYPE 
     CARD8 = SYSTEM.CARD8;
     RunBuf = ARRAY [0..rbLen-1] OF CARD8;
     Run = RECORD
        ch: IOChan.ChanId;
        ptr: CARDINAL;
        len: CARDINAL;
        last: Key;
        buf: POINTER TO RunBuf;
      END;
VAR 
    runCount: INTEGER;
    run:  ARRAY [1..runLimit] OF Run;

  PROCEDURE OpenRun;
  VAR res  : ChanConsts.OpenResults;
      name: ARRAY [0..16] OF CHAR;
  BEGIN
    WholeStr.IntToStr(runCount, name);
    Strings.Insert("run", 0, name);
    INC(runCount);
    WITH run[runCount] DO
      RndFile.OpenClean(ch, name, RndFile.write+RndFile.read+RndFile.old+RndFile.raw, res);
      ptr := 0;
      len := 0;
      last:= 0;
      NEW(buf);
    END
  END OpenRun;

  PROCEDURE FlushRun(VAR r:Run);
  BEGIN
    IOChan.RawWrite(r.ch, SYSTEM.ADR(r.buf^), r.ptr);
    r.ptr := 0;
  END FlushRun;

  PROCEDURE PutRun(x: Key);
  VAR dx: Key;
  BEGIN 
    WITH run[runCount] DO
      IF ptr + 4 >= SIZE(RunBuf) THEN FlushRun(run[runCount]) END;
      dx := x - last;
      WHILE (dx > 127) DO 
        buf^[ptr] := dx MOD 128 + 128;
        INC(ptr);
        dx := dx DIV 128 
      END;
      buf^[ptr] := dx;
      INC(ptr);
      last := x;
    END
  END PutRun;

  PROCEDURE ReadRunBuf(VAR r:Run);
  BEGIN
    r.ptr := 0;
    IOChan.RawRead(r.ch, SYSTEM.ADR(r.buf^), SIZE(RunBuf), r.len);
    IF r.len = 0 THEN  RndFile.Close(r.ch) END;
  END ReadRunBuf;

  PROCEDURE ResetRuns;
   VAR i : INTEGER; 
  BEGIN
    FOR i := 1 TO runCount DO 
      IF run[i].ptr > 0 THEN  FlushRun(run[i]) END;
      RndFile.SetPos(run[i].ch, RndFile.StartPos(run[i].ch));
      ReadRunBuf(run[i]);
      run[i].last:= 0;
    END;
  END ResetRuns;

  PROCEDURE NextByte(VAR r:Run):CARD8; 
  VAR b : CARD8;
  BEGIN
    IF r.ptr >= r.len THEN  
      IF r.len = 0 THEN  RETURN 0 END;
      ReadRunBuf(r);
    END;
    b := r.buf^[r.ptr];
    INC(r.ptr);
    RETURN b
  END NextByte;

  PROCEDURE GetRun(VAR r:Run; VAR res:Key; VAR ok:BOOLEAN);
  VAR b, x, s:CARDINAL; 
  BEGIN
    x := 0; s := 1; 
    b := NextByte(r);
    WHILE b > 127 DO 
      INC(x, (b - 128)*s); 
      s := s * 128; 
      b := NextByte(r);
    END;
    INC(x, b * s); 
    res := r.last + x;
    r.last := res;
    ok := r.len > 0;
  END GetRun;

  PROCEDURE SortIn(l, r: INTEGER);
    VAR i, j: INTEGER; w, x: Key;
   BEGIN
    i := l; j := r;
    x := inbuf[(l+r) DIV 2];
    REPEAT
      WHILE inbuf[i] < x DO INC(i) END;
      WHILE x < inbuf[j] DO DEC(j) END;
      IF i <= j THEN
        w := inbuf[i]; inbuf[i] := inbuf[j]; inbuf[j] := w;
        INC(i); DEC(j)
      END
    UNTIL i > j;
    IF l < j THEN SortIn(l, j) END;
    IF i < r THEN SortIn(i, r) END;
   END SortIn;
  
  PROCEDURE Distribute;
  VAR  i, len, locsRead : CARDINAL;
       input: IOChan.ChanId;
       res  : ChanConsts.OpenResults;
  BEGIN
    RndFile.OpenOld(input, "input", RndFile.raw, res);
    runCount := 0;
    LOOP
      IOChan.RawRead(input, SYSTEM.ADR(inbuf), SIZE(inbuf), locsRead);
      IF locsRead < 4 THEN EXIT END;
      len := locsRead DIV 4;
      SortIn(1, len);
      OpenRun; 
      FOR i := 1 TO len DO PutRun(inbuf[i]) END;
    END;
    RndFile.Close(input);
  END Distribute;

VAR 
  runTop: ARRAY [1..runLimit] OF Key; 

  PROCEDURE Merge;
    VAR i, imin  : INTEGER; ok:BOOLEAN;
  BEGIN
    OpenOut;
    ResetRuns;
    FOR i := 1 TO runCount DO 
      GetRun(run[i], runTop[i], ok) 
    END;
    REPEAT
      imin := 1;
      FOR i := 1 TO runCount DO IF runTop[i] < runTop[imin] THEN imin:= i END END;
      PutOut(runTop[imin]);
      GetRun(run[imin], runTop[imin], ok);
      IF ~ok THEN
        IF imin < runCount  THEN
          run[imin] := run[runCount];
          runTop[imin] := runTop[runCount]
        END;
        DEC(runCount);
      END;
    UNTIL runCount < 1;
    CloseOut;
  END Merge;


BEGIN
  Distribute;
  Merge;
END sort.
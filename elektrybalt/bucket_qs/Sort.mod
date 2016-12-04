MODULE Sort;
IMPORT IOChan, ChanConsts, IOConsts, SeqFile, RndFile, RawIO;
IMPORT SYSTEM, Strings, WholeStr;

CONST HeapLim = 25*1024*1024;
      spillLimit = 300; 
      MW = 65536;

VAR 
    spill: ARRAY [0..spillLimit] OF IOChan.ChanId;
    mbuf:  ARRAY [0..spillLimit] OF CARDINAL; 
    spno: INTEGER;
    inbuf: ARRAY [0..1023] OF CARDINAL;
    bkt: ARRAY [0..MW] OF RECORD
        cnt:CARDINAL;
        cno: INTEGER;
    END;
    heap: ARRAY [1..HeapLim] OF CARDINAL; 

PROCEDURE OpenSpill(i : CARDINAL);
  VAR res : ChanConsts.OpenResults;
      name: ARRAY [0..16] OF CHAR;
  BEGIN     
    WholeStr.IntToStr(i, name);
    Strings.Insert("spill", 0, name);
    SeqFile.OpenWrite(spill[i], name, SeqFile.raw+SeqFile.read+SeqFile.old, res);
  END OpenSpill;

  PROCEDURE sort (l, r: INTEGER);
    VAR i, j: INTEGER; w, x: CARDINAL;
   BEGIN
    i := l; j := r;
    x := heap[(l+r) DIV 2];
    REPEAT
      WHILE heap[i] < x DO i := i+1 END;
      WHILE x < heap[j] DO j := j-1 END;
      IF i <= j THEN
        w := heap[i]; heap[i] := heap[j]; heap[j] := w;
        i := i+1; j := j-1
      END
    UNTIL i > j;
    IF l < j THEN sort(l, j) END;
    IF i < r THEN sort(i, r) END
   END sort;

PROCEDURE SortFile();
VAR 
    s, x : CARDINAL;
    i, n, k : INTEGER;
    input  : IOChan.ChanId;
    output: IOChan.ChanId;
    res  : ChanConsts.OpenResults;
    locsRead : CARDINAL;
BEGIN
    SeqFile.OpenRead(input, "input", SeqFile.raw, res);

    FOR k := 0 TO MW-1 DO bkt[k].cnt := 0  END;
    RawIO.Read(input, x);
    WHILE  IOChan.ReadResult(input) = IOConsts.allRight DO
      k := x DIV MW;
      INC(bkt[k].cnt);
      RawIO.Read(input, x);
    END;

    spno := 0;
    bkt[0].cno := spno;
    s := bkt[0].cnt;
    FOR k := 1 TO MW-1 DO 
      IF s + bkt[k].cnt > HeapLim THEN  spno := spno + 1;  s := 0 END;
      s := s + bkt[k].cnt;
      bkt[k].cno := spno;
    END;

    FOR k := 0 TO spno DO OpenSpill(k) END;

    SeqFile.Reread(input);
    RawIO.Read(input, x);
    WHILE  IOChan.ReadResult(input) = IOConsts.allRight DO
      k := x DIV MW;
      RawIO.Write(spill[bkt[k].cno], x);
      RawIO.Read(input, x);
    END;
    SeqFile.Close(input);

    SeqFile.OpenWrite(output, 'output', SeqFile.raw+SeqFile.old, res);
    FOR k := 0 TO spno DO SeqFile.Reread(spill[k]) END;
    FOR k := 0 TO spno DO 
      IOChan.RawRead(spill[k], SYSTEM.ADR(heap), SIZE(heap), locsRead);
      n := locsRead DIV 4;
      sort(1, n);
      IOChan.RawWrite(output, SYSTEM.ADR(heap), locsRead);
    END;
    SeqFile.Close(output);
    FOR k := 0 TO spno DO  SeqFile.Close(spill[k])  END;
END SortFile;

BEGIN
  SortFile;
END Sort.

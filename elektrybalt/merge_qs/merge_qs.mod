MODULE merge_qs;

IMPORT IOConsts, ChanConsts, IOChan, SeqFile, RawIO;
IMPORT SYSTEM, Strings, WholeStr;

CONST HeapLim = 25*1024*1024;
      spillLimit = 300; 
VAR 
    dest: IOChan.ChanId;
    spill: ARRAY [0..spillLimit] OF IOChan.ChanId;
    mbuf:  ARRAY [0..spillLimit] OF CARDINAL; 
    spno: INTEGER;
    heap: ARRAY [1..HeapLim] OF CARDINAL; 

PROCEDURE OpenSpill(i : CARDINAL);
  VAR res  : ChanConsts.OpenResults;
      name: ARRAY [0..16] OF CHAR;
  BEGIN     
    spno:= i;
    WholeStr.IntToStr(spno, name);
    Strings.Insert("spill", 0, name);
    SeqFile.OpenWrite(spill[spno], name, SeqFile.raw+SeqFile.read+SeqFile.old, res);
    dest := spill[spno];
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
  
  PROCEDURE Distribute;
  VAR  n, locsRead : CARDINAL;
       input: IOChan.ChanId;
       res  : ChanConsts.OpenResults;
  BEGIN
    SeqFile.OpenRead(input, "input", SeqFile.raw, res);
    spno := -1;
    LOOP
      IOChan.RawRead(input, SYSTEM.ADR(heap), SIZE(heap), locsRead);
      IF locsRead < 4 THEN EXIT END;
      n := locsRead DIV 4;
      sort(1, n);
      OpenSpill(spno + 1); 
      IOChan.RawWrite(dest, SYSTEM.ADR(heap), n*4);
    END;
    SeqFile.Close(input);
  END Distribute;

  PROCEDURE Merge;
    VAR i,m  : INTEGER;
        output: IOChan.ChanId;
        res: ChanConsts.OpenResults;
  BEGIN
    SeqFile.OpenWrite(output, 'output', SeqFile.raw+SeqFile.old, res);
    FOR i := 0 TO spno DO SeqFile.Reread(spill[i]) END;
    FOR i := 0 TO spno DO RawIO.Read(spill[i], mbuf[i]) END;
    LOOP
      m := 0;
      FOR i := 1 TO spno DO 
        IF mbuf[i] < mbuf[m] THEN m:= i END;
      END;
      RawIO.Write(output, mbuf[m]);
      RawIO.Read(spill[m], mbuf[m]);
      IF IOChan.ReadResult(spill[m]) # IOConsts.allRight  THEN
        SeqFile.Close(spill[m]);
        IF m < spno  THEN
          spill[m] := spill[spno];
          mbuf[m] := mbuf[spno]
        END;
        DEC(spno);
        IF spno < 0 THEN EXIT END;
      END;
    END;
    SeqFile.Close(output);
  END Merge;

BEGIN
  Distribute; 
  Merge;
END merge_qs.
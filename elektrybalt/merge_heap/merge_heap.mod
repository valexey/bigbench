MODULE merge_heap;
IMPORT IOConsts, ChanConsts, IOChan, SeqFile, RawIO;
IMPORT Strings, WholeStr;


CONST HeapLim = 25*1024*1024;
      spillLimit = 300; 

VAR dest: IOChan.ChanId;
    spill: ARRAY [0..spillLimit] OF IOChan.ChanId;
    mbuf:  ARRAY [0..spillLimit] OF CARDINAL; 
    spno : INTEGER;
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

  PROCEDURE sift(i, upper: INTEGER);
    VAR j:INTEGER; x: CARDINAL;
  BEGIN
    j := 2*i;
    x := heap[i];
    IF  (j < upper) & (heap[j] > heap[j+1]) THEN INC(j) END;
    WHILE  (j <= upper) & (x > heap[j]) DO
      heap[i] := heap[j];  
      i := j;  
      j := 2*j;
      IF (j < upper) & (heap[j] > heap[j+1]) THEN INC(j) END
    END;
    heap[i] := x
  END sift;

  PROCEDURE Distribute;
    VAR  
      idx, lim, heapLen, halfHS: INTEGER;
      elem: CARDINAL;
      input: IOChan.ChanId;
      res  : ChanConsts.OpenResults;
  BEGIN
    SeqFile.OpenRead(input, "input", SeqFile.raw, res);
    OpenSpill(0);
    (* fill heap *)
    heapLen := 0;
    RawIO.Read(input, elem);
    WHILE  (heapLen < HeapLim) & (IOChan.ReadResult(input) = IOConsts.allRight) DO
      INC(heapLen);
      heap[heapLen] := elem;  
      RawIO.Read(input, elem);
    END;
    halfHS := heapLen DIV 2;
    FOR idx := halfHS TO 1 BY -1 DO sift(idx, heapLen) END;
    (* sieve *)
    lim := heapLen;  
    WHILE  IOChan.ReadResult(input) = IOConsts.allRight DO
      RawIO.Write(dest, heap[1]);
      IF heap[1] <= elem  THEN
        heap[1] := elem;  
        sift(1, lim)
      ELSE
        heap[1] := heap[lim];  
        sift(1, lim-1);  
        heap[lim] := elem;
        IF lim < halfHS THEN sift(lim, heapLen) END;
        DEC(lim);  
        IF lim = 0 THEN 
          OpenSpill(spno+1);
          lim := heapLen  
        END
      END;
      RawIO.Read(input, elem);
    END;
    (* flush heap *)
    idx := heapLen;
    REPEAT  
      RawIO.Write(dest, heap[1]);
      heap[1] := heap[lim];
      sift(1, lim-1);  
      heap[lim] := heap[idx];
      DEC(idx);
      IF lim < halfHS THEN sift(lim, idx)  END;
      DEC(lim);  
    UNTIL lim = 0;
    IF idx > 0 THEN OpenSpill(spno + 1) END; 
    WHILE idx > 0 DO
      RawIO.Write(dest, heap[1]); 
      heap[1] := heap[idx]; 
      DEC(idx); 
      sift(1, idx)
    END;
    SeqFile.Close(input);
  END Distribute;

  PROCEDURE Merge;
    VAR i,m: INTEGER;
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
END merge_heap.
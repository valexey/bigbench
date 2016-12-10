MODULE FileSort;

IMPORT File := CFiles;

CONST
	IoBufSize = 4096 * 128;
	SectorBufSize = 4096 * 3 * 6;
	PositionsCount = 640 * 1024;

	SectorsCount = 256;
	ModCount = 65536 DIV SectorsCount * 65536;

TYPE
	Sector = RECORD
		i, last: INTEGER;
		v: ARRAY SectorBufSize OF CHAR
	END;

	SectorPosition = RECORD
		pos, next: INTEGER
	END;

VAR
	out: RECORD
		buf: ARRAY IoBufSize OF CHAR;
		i: INTEGER
	END;
	fin, ftmp, fout: File.File;

	posTop, filePos: INTEGER;
	sectors: ARRAY SectorsCount - 1 OF Sector;
	counts: ARRAY ModCount OF INTEGER;
	positions: ARRAY PositionsCount OF SectorPosition;

PROCEDURE MarkPos(VAR s: Sector);
BEGIN
	positions[posTop].pos := filePos;
	positions[posTop].next := s.last;
	s.last := posTop;
	INC(filePos);
	INC(posTop)
END MarkPos;

PROCEDURE WriteFromCounts(base: INTEGER);
VAR i, j, len: INTEGER;
BEGIN
	j := out.i;
	FOR i := 0 TO LEN(counts) - 1 DO
		WHILE counts[i] > 0 DO
			DEC(counts[i]);

			out.buf[j + 0] := CHR(i MOD 256);
			out.buf[j + 1] := CHR(i DIV 256 MOD 256);
			out.buf[j + 2] := CHR(i DIV 65536);
			out.buf[j + 3] := CHR(base);

			INC(j, 4);
			IF j >= LEN(out.buf) THEN
				j := 0;
				len := File.Write(fout, out.buf, 0, LEN(out.buf));
				ASSERT(len = LEN(out.buf))
			END
		END
	END;
	out.i := j
END WriteFromCounts;

PROCEDURE IncCounts(buf: ARRAY OF CHAR; count: INTEGER);
VAR i: INTEGER;
BEGIN
	ASSERT(count MOD 3 = 0);
	WHILE count > 0 DO
		DEC(count, 3);
		i := ORD(buf[count])
		   + ORD(buf[count + 1]) * 256
		   + ORD(buf[count + 2]) * 65536;
		INC(counts[i])
	END
END IncCounts;

PROCEDURE WriteSector(VAR s: Sector; v: INTEGER);
CONST
	Mult = SectorBufSize DIV 4096;
	Div = File.GiB DIV 4096;
VAR ok: BOOLEAN;
BEGIN
	IF (s.i > 0) OR (s.last >= 0) THEN
		IncCounts(s.v, s.i);
		WHILE s.last >= 0 DO
			ok := File.Seek(ftmp,
				positions[s.last].pos * Mult DIV Div,
				positions[s.last].pos * Mult MOD Div * 4096
			);
			s.last := positions[s.last].next;
			ok := ok & (LEN(s.v) = File.Read(ftmp, s.v, 0, LEN(s.v)));
			ASSERT(ok);
			IncCounts(s.v, LEN(s.v))
		END;
		WriteFromCounts(v)
	END
END WriteSector;

PROCEDURE AddToSector(VAR s: Sector; v: ARRAY OF CHAR; ofs: INTEGER);
VAR len: INTEGER;
BEGIN
	IF s.i = LEN(s.v) THEN
		MarkPos(s);
		len := File.Write(ftmp, s.v, 0, LEN(s.v));
		ASSERT(len = LEN(s.v));
		s.i := 0
	END;
	s.v[s.i]     := v[ofs];
	s.v[s.i + 1] := v[ofs + 1];
	s.v[s.i + 2] := v[ofs + 2];
	INC(s.i, 3)
END AddToSector;

PROCEDURE Read;
VAR r, i, ind: INTEGER;
	buf: ARRAY IoBufSize OF CHAR;
BEGIN
	filePos := 0;
	posTop := 0;
	FOR i := 0 TO LEN(sectors) - 1 DO
		sectors[i].i := 0;
		sectors[i].last := -1
	END;

	REPEAT
		r := File.Read(fin, buf, 0, LEN(buf));
		FOR i := 0 TO r - 4 BY 4 DO
			IF buf[i + 3] = 0X THEN
				ind := ORD(buf[i]) +
				256 * (ORD(buf[i + 1]) + 
				256 *  ORD(buf[i + 2]));
				INC(counts[ind])
			ELSE
				AddToSector(sectors[ORD(buf[i + 3]) - 1], buf, i)
			END
		END
	UNTIL r < LEN(buf)
END Read;

PROCEDURE Go;
VAR ok: BOOLEAN;
	w, i: INTEGER;
BEGIN
	fin := File.Open("input", 0, "rb");
	ftmp := File.Open("TEMP", 0, "w+b");

	Read;
	File.Close(fin);

	fout := File.Open("output", 0, "wb");

	WriteFromCounts(0);
	FOR i := 0 TO LEN(sectors) - 1 DO
		WriteSector(sectors[i], i + 1)
	END;
	IF out.i > 0 THEN
		w := File.Write(fout, out.buf, 0, out.i);
		ASSERT(w = out.i)
	END;

	File.Close(fout);
	File.Close(ftmp);
	ok := File.Remove("TEMP", 0)
END Go;

BEGIN
	Go
END FileSort.

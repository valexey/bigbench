MODULE FileSort;

IMPORT File := CFiles;

CONST
	Passes = 4;
	IoBufSize = 4096 * 16;
	SectorBufSize = 1024 * Passes;
	PositionsCount = 62000000 DIV (4 * 2);

	SectorsCount = 65536 DIV Passes;
	ModCount = 65536;

TYPE
	Sector = RECORD
		i, last: INTEGER;
		v: ARRAY SectorBufSize OF CHAR
	END;

	SectorPosition = RECORD
		pos, next: INTEGER
	END;

VAR
	counts: ARRAY ModCount OF INTEGER;
	out: RECORD
		buf: ARRAY IoBufSize OF CHAR;
		i: INTEGER
	END;
	fin, ftmp, fout: File.File;

	posTop, filePos, pass: INTEGER;
	sectors: ARRAY SectorsCount OF Sector;
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
	b2, b3: CHAR;
BEGIN
	b2 := CHR(base MOD 256);
	b3 := CHR(base DIV 256);
	j := out.i;
	FOR i := 0 TO LEN(counts) - 1 DO
		WHILE counts[i] > 0 DO
			DEC(counts[i]);

			out.buf[j + 0] := CHR(i MOD 256);
			out.buf[j + 1] := CHR(i DIV 256);
			out.buf[j + 2] := b2;
			out.buf[j + 3] := b3;

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
BEGIN
	ASSERT(~ODD(count));
	WHILE count > 0 DO
		DEC(count, 2);
		INC(counts[ORD(buf[count]) + ORD(buf[count + 1]) * 256])
	END
END IncCounts;

PROCEDURE WriteSector(VAR s: Sector; v: INTEGER);
VAR ok: BOOLEAN;
	PosDivider: INTEGER;
BEGIN
	PosDivider := 1024 * 1024 * 1024 DIV SectorBufSize;
	IF (s.i > 0) OR (s.last >= 0) THEN
		IncCounts(s.v, s.i);
		WHILE s.last >= 0 DO
			ok := File.Seek(ftmp,
				positions[s.last].pos DIV PosDivider,
				positions[s.last].pos MOD PosDivider * SectorBufSize
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
	INC(s.i, 2)
END AddToSector;

PROCEDURE Read;
VAR r, i: INTEGER;
	buf: ARRAY IoBufSize OF CHAR;
	ok: BOOLEAN;
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
			IF pass = ORD(buf[i + 3]) DIV (256 DIV Passes) THEN
				AddToSector(sectors[
					(ORD(buf[i + 2]) + ORD(buf[i + 3]) * 256) MOD LEN(sectors)
					], buf, i
				)
			END
		END
	UNTIL r < LEN(buf);
	ok := File.Seek(fin, 0, 0);
	ASSERT(ok)
END Read;

PROCEDURE Go;
VAR ok: BOOLEAN;
	w, i: INTEGER;
BEGIN
	fin := File.Open("input", 0, "rb");
	ftmp := File.Open("TEMP", 0, "w+b");
	fout := File.Open("output", 0, "wb");

	FOR pass := 0 TO Passes - 1 DO
		Read;
		FOR i := 0 TO LEN(sectors) - 1 DO
			WriteSector(sectors[i], pass * SectorsCount + i)
		END;
		File.Close(ftmp);
		ftmp := File.Open("TEMP", 0, "w+b")
	END;
	IF out.i > 0 THEN
		w := File.Write(fout, out.buf, 0, out.i);
		ASSERT(w = out.i)
	END;

	File.Close(fout);
	File.Close(ftmp);
	ok := File.Remove("TEMP", 0);
	File.Close(fin)
END Go;

BEGIN
	Go
END FileSort.

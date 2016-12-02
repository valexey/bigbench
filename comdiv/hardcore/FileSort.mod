(* Посвящаю модуль всем, кто любит хардкор *)
MODULE FileSort;

IMPORT File := CFiles, CLI, Out;

CONST
	SectorBufSize = 1024;

	SectorsCount = 65536;
	ModCount = (65536 * (65536 DIV 4)) DIV (SectorsCount DIV 4);

TYPE
	Sector = RECORD
		name: ARRAY 12 OF CHAR;
		i: INTEGER;
		v: ARRAY SectorBufSize OF CHAR
	END;

VAR
	sectors: ARRAY SectorsCount OF Sector;
	counts: ARRAY ModCount OF INTEGER;
	out: RECORD
			buf: ARRAY 4096 OF CHAR;
			i: INTEGER
		END;
	fin, fout: File.File;

PROCEDURE AddToSector(VAR s: Sector; v: ARRAY OF CHAR; ofs: INTEGER);
VAR f: File.File;
	len: INTEGER;
BEGIN
	IF s.i = LEN(s.v) THEN
		IF s.name[0] = 0X THEN
			s.name[0] := CHR(ORD("A") + ORD(v[ofs + 3]) DIV 16);
			s.name[1] := CHR(ORD("A") + ORD(v[ofs + 3]) MOD 16);
			s.name[2] := CHR(ORD("A") + ORD(v[ofs + 2]) DIV 16);
			s.name[3] := CHR(ORD("A") + ORD(v[ofs + 2]) MOD 16);
			s.name[4] := ".";
			s.name[5] := "T";
			s.name[6] := "M";
			s.name[7] := "P";
			s.name[8] := 0X;
			f := File.Open(s.name, 0, "wb")
		ELSE
			f := File.Open(s.name, 0, "ab")
		END;
		ASSERT(f # NIL);
		len := File.Write(f, s.v, 0, LEN(s.v));
		ASSERT(len = LEN(s.v));
		File.Close(f);
		s.i := 0
	END;
	s.v[s.i] := v[ofs];
	INC(s.i);
	s.v[s.i] := v[ofs + 1];
	INC(s.i)
END AddToSector;

PROCEDURE WriteFromCounts(base: INTEGER);
VAR i, len: INTEGER;
BEGIN
	FOR i := 0 TO SectorsCount - 1 DO
		WHILE counts[i] > 0 DO
			DEC(counts[i]);

			out.buf[out.i + 3] := CHR(base DIV 256);
			out.buf[out.i + 2] := CHR(base MOD 256);
			out.buf[out.i + 1] := CHR(i DIV 256);
			out.buf[out.i + 0] := CHR(i MOD 256);

			out.i := (out.i + 4) MOD LEN(out.buf);
			IF out.i = 0 THEN
				len := File.Write(fout, out.buf, 0, LEN(out.buf));
				ASSERT(len = LEN(out.buf))
			END
		END
	END
END WriteFromCounts;

PROCEDURE WriteSector(VAR s: Sector; v: INTEGER);
VAR i, r: INTEGER;
	buf: ARRAY 4096 OF CHAR;
	f: File.File;
	del: BOOLEAN;
BEGIN
	IF (s.i > 0) OR (s.name[0] # 0X) THEN
		WHILE s.i > 0 DO
			DEC(s.i, 2);
			INC(counts[ORD(s.v[s.i]) + ORD(s.v[s.i + 1]) * 256])
		END;
		IF s.name[0] # 0X THEN
			f := File.Open(s.name, 0, "rb");
			ASSERT(f # NIL);

			REPEAT
				r := File.Read(f, buf, 0, LEN(buf));
				FOR i := 0 TO r - 2 BY 2 DO
					INC(counts[ORD(buf[i]) + ORD(buf[i + 1]) * 256])
				END
			UNTIL r < LEN(buf);

			File.Close(f);
			del := File.Remove(s.name, 0)
		END;
		WriteFromCounts(v)
	END
END WriteSector;

PROCEDURE Go;
VAR r, w, i: INTEGER;
	buf: ARRAY 4096 OF CHAR;
	nin, nout: ARRAY 256 OF CHAR;
	ninLen, noutLen: INTEGER;
	copy: BOOLEAN;
BEGIN
	IF CLI.count < 3 THEN
		Out.String("Usage:   filesort input.file output.file"); Out.Ln
	ELSE
		ninLen := 0;
		noutLen := 0;
		copy := CLI.Get(nin, ninLen, 1) & CLI.Get(nout, noutLen, 2);
		ASSERT(copy);
		fin := File.Open(nin, 0, "rb");
		fout := File.Open(nout, 0, "wb");
		ASSERT((fin # NIL) & (fout # NIL));

		REPEAT
			r := File.Read(fin, buf, 0, LEN(buf));
			FOR i := 0 TO r - 4 BY 4 DO
				AddToSector(sectors[ORD(buf[i + 3]) * 256 + ORD(buf[i + 2])], buf, i)
			END
		UNTIL r < LEN(buf);

		File.Close(fin);

		FOR i := 0 TO SectorsCount - 1 DO
			WriteSector(sectors[i], i)
		END;

		IF out.i > 0 THEN
			w := File.Write(fout, out.buf, 0, out.i);
			ASSERT(w = out.i)
		END;
		File.Close(fout)
	END
END Go;

BEGIN
	Go
END FileSort.

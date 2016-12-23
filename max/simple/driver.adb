with Interfaces;
with Ada.Streams.Stream_IO;
with Ada.Sequential_IO;
with Ada.Directories;
with Ada.Containers.Generic_Constrained_Array_Sort;
with Ada.Unchecked_Deallocation;

procedure Driver is
   use type Ada.Directories.File_Size;
   use type Ada.Streams.Stream_Element_Offset;

   Input_Name  : constant String := "input";
   Output_Name : constant String := "output";

   File_Size : constant Ada.Directories.File_Size :=
     Ada.Directories.Size (Input_Name);
   --  Size of input file in bytes

   type Value is new Interfaces.Unsigned_32;

   Value_Size : constant :=
     Value'Size / Ada.Streams.Stream_Element'Size;
   --  Size of Value in bytes

   Piece_Size : constant := 100 * 1024 * 1024;
   --  Size of Piece in bytes

   Values_Per_Piece : constant := Piece_Size / Value_Size;
   --  Number of values per one Piece

   type Piece_Index is new Positive range
     1 .. Natural ((File_Size - 1) / Piece_Size) + 1;
   --  Index of Piece in input file

   function Piece_File_Name (Index : Piece_Index) return String;
   --  Return file name for temporary storage of the Piece with given Index

   procedure Write_All_Pieces;
   --  Read input in chunk of Piece_Size, sort each chunk and write to
   --  corresponding file

   procedure Join_All_Pieces;
   --  Join each piece in a sorted steam and write result to output

   package Value_IO is new Ada.Sequential_IO (Value);

   ---------------------
   -- Join_All_Pieces --
   ---------------------

   procedure Join_All_Pieces is

      Output : Value_IO.File_Type;

      type File_Index is new Piece_Index;

      Input : array (File_Index) of Value_IO.File_Type;
      Item  : array (Piece_Index) of Value;
      Map   : array (Piece_Index) of File_Index;
      Last  : Piece_Index := Item'Last;
      Index : Piece_Index;
      Found : Value;
      Count : Ada.Directories.File_Size := File_Size / Value_Size;
   begin
      Value_IO.Create (Output, Name => Output_Name);

      for J in Item'Range loop
         Map (J) := File_Index (J);
         Value_IO.Open
           (Input (Map (J)), Value_IO.In_File, Piece_File_Name (J));
         Value_IO.Read (Input (Map (J)), Item (J));
      end loop;

      while Count > 0 loop
         --  Look for index of the least Value of Item
         Index := 1;
         Found := Item (Index);

         for J in 2 .. Last loop
            if Item (J) < Found then
               Index := J;
               Found := Item (Index);
            end if;
         end loop;

         Value_IO.Write (Output, Found);
         Count := Count - 1;

         if not Value_IO.End_Of_File (Input (Map (Index))) then
            loop
               Value_IO.Read (Input (Map (Index)), Item (Index));

               exit when Item (Index) /= Found;

               Value_IO.Write (Output, Found);
               Count := Count - 1;

               exit when Count = 0
                 or Value_IO.End_Of_File (Input (Map (Index)));
            end loop;
         elsif Last > 1 then
            Item (Index) := Item (Last);
            Map (Index) := Map (Last);
            Last := Last - 1;
         end if;
      end loop;
   end Join_All_Pieces;

   ----------------------
   -- Piece_File_Name --
   ----------------------

   function Piece_File_Name (Index : Piece_Index) return String is
      Name  : String := Piece_Index'Image (Index);
   begin
      Name (1) := 'T';
      return Name;
   end Piece_File_Name;

   ----------------------
   -- Write_All_Pieces --
   ----------------------

   procedure Write_All_Pieces is
      subtype Index_Type is Natural range 1 .. Values_Per_Piece;
      type Piece_Half is array (Index_Type) of Value;

      type Piece_Access is access all Piece_Half;

      procedure Read_Piece
        (Data  : in out Piece_Half;
         Input : Ada.Streams.Stream_IO.File_Type);
      --  Read Piece_Half from given Input

      procedure Join (Left, Right : Piece_Half; Index : Piece_Index);
      --  Join two Piece_Half and write into temporary file with given Index

      procedure Free is
        new Ada.Unchecked_Deallocation (Piece_Half, Piece_Access);

      procedure Do_Sort is new Ada.Containers.Generic_Constrained_Array_Sort
        (Index_Type   => Index_Type,
         Element_Type => Value,
         Array_Type   => Piece_Half);

      task Sorter is
         entry Start_Sorting (Piece : Piece_Access);
         entry Complete;
         entry Stop;
      end Sorter;

      ------------
      -- Sorter --
      ------------

      task body Sorter is
         Data  : Piece_Access;
      begin
         loop
            select
               accept Start_Sorting (Piece : Piece_Access) do
                  Data := Piece;
               end Start_Sorting;

               Do_Sort (Data.all);

               accept Complete;
            or
               accept Stop;
               exit;
            end select;
         end loop;
      end Sorter;

      -----------------
      -- Read_Piece --
      -----------------

      procedure Read_Piece
        (Data  : in out Piece_Half;
         Input : Ada.Streams.Stream_IO.File_Type)
      is
         Piece : Ada.Streams.Stream_Element_Array (1 .. Piece_Size);
         for Piece'Address use Data'Address;
         pragma Import (Ada, Piece);

         Bytes : Ada.Streams.Stream_Element_Offset;
         Last  : Index_Type;
      begin
         Ada.Streams.Stream_IO.Read (Input, Piece, Bytes);
         Last := Index_Type (Bytes / Value_Size);

         if Last < Data'Last then
            Data (Last + 1 .. Data'Last) := (others => Value'Last);
         end if;
      end Read_Piece;

      procedure Join (Left, Right : Piece_Half; Index : Piece_Index) is
         Name   : constant String := Piece_File_Name (Index);
         Output : Value_IO.File_Type;

         L, R : Index_Type'Base := 1;
      begin
         Value_IO.Create
           (Output, Name => Name, Form => "SHARED=YES");

         loop
            if L <= Left'Last and R <= Right'Last then
               if Left (L) < Right (R) then
                  Value_IO.Write (Output, Left (L));
                  L := L + 1;
               else
                  Value_IO.Write (Output, Right (R));
                  R := R + 1;
               end if;
            elsif L <= Left'Last then
               Value_IO.Write (Output, Left (L));
               L := L + 1;
            elsif R <= Right'Last then
               Value_IO.Write (Output, Right (R));
               R := R + 1;
            else
               exit;
            end if;
         end loop;

         Value_IO.Close (Output);
      end Join;

      Left, Right : Piece_Access := new Piece_Half;
      Input       : Ada.Streams.Stream_IO.File_Type;

   begin
      Ada.Streams.Stream_IO.Open
        (Input,
         Ada.Streams.Stream_IO.In_File,
         Input_Name);

      for J in Piece_Index loop
         Read_Piece (Left.all, Input);
         Sorter.Start_Sorting (Left);
         Read_Piece (Right.all, Input);
         Do_Sort (Right.all);
         Sorter.Complete;

         Join (Left.all, Right.all, J);
      end loop;

      Free (Left);
      Free (Right);
      Sorter.Stop;
      Ada.Streams.Stream_IO.Close (Input);
   end Write_All_Pieces;

begin
   Write_All_Pieces;
   Join_All_Pieces;
end Driver;

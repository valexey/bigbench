with Interfaces;
with Ada.Streams.Stream_IO;
with Ada.Sequential_IO;
with Ada.Directories;
with Ada.Containers.Generic_Array_Sort;
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

   Piece_Size : constant := 30 * 1024 * 1024;
   --  Size of Piece in bytes

   Values_Per_Piece : constant := Piece_Size / Value_Size;
   --  Number of values per one Piece

   subtype Index_Type is Natural range 1 .. Values_Per_Piece;
   type Piece is array (Index_Type) of Value;

   type Piece_Index is new Positive range
     1 .. Natural ((File_Size - 1) / Piece_Size) + 1;

   function Piece_File_Name (Index : Piece_Index) return String;
   --  Return file name for temporary storage of the Piece with given Index

   procedure Read_Piece
     (Data  : in out Piece;
      Input : Ada.Streams.Stream_IO.File_Type);
   --  Read Piece from given Input

   procedure Write_Piece (Data : Piece; Index : Piece_Index);
   --  Write Piece with given index to temporary file

   procedure Write_All_Pieces;
   --  Read input in chunk of Piece_Size, sort each chunk and write to
   --  corresponding file

   procedure Join_All_Pieces;
   --  Join each piece in a sorted steam and write result to output

   ---------------------
   -- Join_All_Pieces --
   ---------------------

   procedure Join_All_Pieces is
      package Value_IO is new Ada.Sequential_IO (Value);

      Output : Value_IO.File_Type;

      type Map_Index is new Piece_Index;
      type Mapping is array (Map_Index range <>) of Piece_Index;

      function Less (Left, Right : Piece_Index) return Boolean;

      procedure Sort is new Ada.Containers.Generic_Array_Sort
        (Index_Type   => Map_Index,
         Element_Type => Piece_Index,
         Array_Type   => Mapping,
         "<"          => Less);

      Input : array (Piece_Index) of Value_IO.File_Type;
      Item  : array (Piece_Index) of Value;

      ----------
      -- Less --
      ----------

      function Less (Left, Right : Piece_Index) return Boolean is
      begin
         return Item (Left) < Item (Right);
      end Less;

      Map   : Mapping (1 .. Item'Length);
      Last  : Map_Index := Map'Last;
      Next  : Value;
   begin
      Value_IO.Create (Output, Name => Output_Name);

      for J in Item'Range loop
         Value_IO.Open
           (Input (J), Value_IO.In_File, Piece_File_Name (J));
         Value_IO.Read (Input (J), Item (J));
         Map (Map_Index (J)) := J;
      end loop;

      Sort (Map);

      for J in 1 .. File_Size / Value_Size loop
         Next := Item (Map (1));
         Value_IO.Write (Output, Next);

         if Value_IO.End_Of_File (Input (Map (1))) then
            Map (1) := Map (Last);
            Last := Last - 1;
            Sort (Map (1 .. Last));
         else
            Value_IO.Read (Input (Map (1)), Item (Map (1)));

            if Next /= Item (Map (1)) then
               Sort (Map (1 .. Last));
            end if;
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

   -----------------
   -- Read_Piece --
   -----------------

   procedure Read_Piece
     (Data  : in out Piece;
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

   ----------------------
   -- Write_All_Pieces --
   ----------------------

   procedure Write_All_Pieces is
      type Piece_Access is access all Piece;

      procedure Free is new Ada.Unchecked_Deallocation (Piece, Piece_Access);

      procedure Do_Sort is new Ada.Containers.Generic_Constrained_Array_Sort
        (Index_Type   => Index_Type,
         Element_Type => Value,
         Array_Type   => Piece);

      protected Queue is
         entry Put
           (Unused : out Piece_Access;
            Piece  : Piece_Access;
            Index  : Piece_Index);

         entry Get
           (Unused : Piece_Access;
            Piece  : out Piece_Access;
            Index  : out Piece_Index);

      private
         Full          : Boolean := False;
         Current_Piece : Piece_Access;
         Current_Index : Piece_Index;
         Unused_Piece  : Piece_Access;
      end Queue;

      task type Sorter;

      -----------
      -- Queue --
      -----------

      protected body Queue is

         entry Get
           (Unused : Piece_Access;
            Piece  : out Piece_Access;
            Index  : out Piece_Index) when Full is
         begin
            Piece := Current_Piece;
            Index := Current_Index;
            Unused_Piece := Unused;
            Full := False;
         end Get;

         entry Put
           (Unused : out Piece_Access;
            Piece  : Piece_Access;
            Index  : Piece_Index) when not Full is
         begin
            Unused := Unused_Piece;
            Current_Piece := Piece;
            Current_Index := Index;
            Full := True;
         end Put;

      end Queue;

      ------------
      -- Sorter --
      ------------

      task body Sorter is
         Data  : Piece_Access;
         Index : Piece_Index;
      begin
         loop
            Queue.Get
              (Unused  => Data,
               Piece   => Data,
               Index   => Index);

            if Data = null then
               exit;
            else
               Do_Sort (Data.all);
               Write_Piece (Data.all, Index);
            end if;
         end loop;
      end Sorter;

      Workers : array (1 .. 2) of Sorter;
      Current : Piece_Access := new Piece;
      Input   : Ada.Streams.Stream_IO.File_Type;

   begin
      Ada.Streams.Stream_IO.Open
        (Input,
         Ada.Streams.Stream_IO.In_File,
         Input_Name);

      for J in Piece_Index loop
         Read_Piece (Current.all, Input);
         Queue.Put (Current, Current, J);

         if Current = null then
            Current := new Piece;
         end if;
      end loop;

      Free (Current);

      for J in Workers'Range loop
         Queue.Put (Current, null, 1);
         Free (Current);
      end loop;

      Ada.Streams.Stream_IO.Close (Input);
   end Write_All_Pieces;

   ------------------
   -- Write_Piece --
   ------------------

   procedure Write_Piece (Data : Piece; Index : Piece_Index) is
      Name   : constant String := Piece_File_Name (Index);
      Output : Ada.Streams.Stream_IO.File_Type;
      Piece : Ada.Streams.Stream_Element_Array (1 .. Piece_Size);
      for Piece'Address use Data'Address;
      pragma Import (Ada, Piece);
   begin
      Ada.Streams.Stream_IO.Create
        (Output, Name => Name, Form => "SHARED=YES");
      Ada.Streams.Stream_IO.Write (Output, Piece);
      Ada.Streams.Stream_IO.Close (Output);
   end Write_Piece;

begin
   Write_All_Pieces;
   Join_All_Pieces;
end Driver;

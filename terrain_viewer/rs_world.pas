unit rs_world;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

const
  TEX_WIDTH = 64;
  TEX_HEIGHT = 64;
  TEXTURE_FNAME = 'level_tex.pnm';

type
  TRGB = array[0..2] of byte;
  PRGB = ^TRGB;
  TPalette_4bit = array[0..15] of TRGB;

  TTile = packed record
      texture_index: word;
      unknown_attrib: byte;
      height_lo: shortint;
      height_hi: shortint;
      heights: array[0..24] of shortint;
  end;
  PTile = ^TTile;

  THeightmap = record
      y_scale: single;
      width, height: word;
      blk: pword;
      tile_count: integer;
      tiles: PTile;
      texture_count: integer;
      textures: array of pbyte;
      texture_index_map: array of integer;
  end;

  { TWorld }

  TWorld = class
    private
      world_texture: pbyte;
      height_texture: pbyte;

      procedure LoadTextures(const tex_fname, texidx_fname: string);
      procedure LoadHeightmap(fname: string);

    public
      heightmap: THeightmap;
      vertex_count: integer;

      property TileWidth: word read heightmap.width;
      property TileHeight: word read heightmap.height;

      procedure LoadFromFiles(const hmp, tex, texmap: string);

      constructor Create;
      destructor Destroy; override;
  end;

procedure pnm_save(const fname: string; const p: pbyte; const w, h: integer);

//**************************************************************************************************
implementation

procedure pnm_save(const fname: string; const p: pbyte; const w, h: integer);
var
  f: file;
  c: PChar;
Begin
  c := PChar(format('P6'#10'%d %d'#10'255'#10, [w, h]));
  AssignFile (f, fname);
  Rewrite (f, 1);
  BlockWrite (f, c^, strlen(c));
  BlockWrite (f, p^, w * h * 3);
  CloseFile (f);
end;

procedure pgm_save(fname: string; p: pbyte; w, h: integer) ;
var
  f: file;
  c: PChar;
Begin
  c := PChar(format('P5'#10'%d %d'#10'255'#10, [w, h]));
  AssignFile (f, fname);
  Rewrite (f, 1);
  BlockWrite (f, c^, strlen(c));
  BlockWrite (f, p^, w * h);
  CloseFile (f);
end;

procedure convert_4bit_to_24bit(const indices: PByte; const w, h: Word; const image: PByte; const pal: TPalette_4bit);
var
  i: Integer;
  index: integer;
  dst: PRGB;
begin
  dst := PRGB(image);
  for i := 0 to w * h div 2 - 1 do begin
      index := indices[i];
      dst[i * 2    ] := pal[(index shr 4) and 15];
      dst[i * 2 + 1] := pal[index and 15];
  end;
end;

procedure CopyTexToXY(image: PByte; texture: PByte; const x, y, stride: integer);
var
  i: integer;
  src, dst: pbyte;
begin
  src := texture;
  dst := image + y * stride + x * 3;
  for i := 0 to TEX_HEIGHT - 1 do begin
      move(src^, dst^, TEX_WIDTH * 3);
      dst += stride;
      src += TEX_WIDTH * 3;
  end;
end;

procedure CopyTileToXY(image: PByte; tile: PByte; const x, y, stride: integer);
var
  i: integer;
  src, dst: pbyte;
begin
  src := tile + 5 * 4;
  dst := image + y * stride + x;
  for i := 0 to 3 do begin
      move(src^, dst^, 4);
      dst += stride;
      src -= 5;
  end;
end;

{ TWorld }

procedure TWorld.LoadTextures(const tex_fname, texidx_fname: string);
var
  f: file;
  buf: pbyte;
  tex_size: integer;
  i: Integer;
  palette: TPalette_4bit;
  image: pbyte;
  palette_size: Integer;
  texture_count: integer;
begin
  AssignFile(f, tex_fname);
  reset(f, 1);

  palette_size := 48;  //16x RGB
  tex_size := TEX_WIDTH * TEX_HEIGHT div 2;
  texture_count := filesize(f) div (tex_size + palette_size);
  //writeln('texture_count: ', texture_count);

  SetLength(heightmap.textures, texture_count);
  heightmap.texture_count := texture_count;

  buf := getmem(tex_size);
  for i := 0 to texture_count - 1 do begin
      image := getmem(TEX_WIDTH * TEX_HEIGHT * 3);
      Blockread(f, buf^, tex_size);
      Blockread(f, palette, palette_size);
      convert_4bit_to_24bit(buf, TEX_WIDTH, TEX_HEIGHT, image, palette);
      heightmap.textures[i] := image;
  end;
  freemem(buf);
  CloseFile(f);

  AssignFile(f, texidx_fname);
  Reset(f, 1);

  texture_count := filesize(f) div 4 - 1;
  SetLength(heightmap.texture_index_map, texture_count);
  Blockread(f, heightmap.texture_index_map[0], texture_count * 4);

  CloseFile(f);
end;

procedure TWorld.LoadHeightmap(fname: string);
var
  f: file;
  buffer: array[0..15] of byte;
  tile_offset: integer;
  blk: pword;
  blk_size: integer;
  tile_count: word;
  i: integer;
begin
  AssignFile(f, fname);
  reset(f, 1);

  //header
  Blockread(f, buffer, 12);
  Blockread(f, buffer, 4);
  Blockread(f, heightmap.y_scale, 4);
  Blockread(f, buffer, 4);
  Blockread(f, tile_count, 2);   //tile count
  Blockread(f, buffer, 2);       //2B?
  Blockread(f, tile_offset, 4);  //tile offset
  Blockread(f, buffer, 4);       //offset?
  Blockread(f, heightmap.width, 2);
  Blockread(f, heightmap.height, 2);

  //blocks / tile indices
  blk_size := heightmap.width * heightmap.height * 2;
  blk := getmem(blk_size);
  Blockread(f, blk^, blk_size);
  heightmap.blk := blk;

  //tiles
  //writeln('filepos: ', FilePos(f)); writeln('tile pos: ', tile_offset);
  Seek(f, tile_offset);
  heightmap.tile_count := tile_count;
  heightmap.tiles := getmem(tile_count * 30);
  for i := 0 to tile_count - 1 do
      Blockread(f, heightmap.tiles[i], 30);

  CloseFile(f);
end;

procedure TWorld.LoadFromFiles(const hmp, tex, texmap: string);
var
  i: Integer;
begin
  LoadHeightmap(hmp);
  LoadTextures(tex, texmap);
  for i := 0 to heightmap.tile_count - 1 do begin
      heightmap.tiles[i].texture_index := heightmap.texture_index_map[heightmap.tiles[i].texture_index];
  end;
end;

constructor TWorld.Create;
begin
  height_texture := nil;
end;

destructor TWorld.Destroy;
begin
  if height_texture <> nil then Freemem(height_texture);
  inherited Destroy;
end;

end.


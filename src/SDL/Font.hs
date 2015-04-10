{-|

Module      : SDL.Font
Description : High-level bindings.
Copyright   : (c) 2015 Siniša Biđin
License     : MIT
Maintainer  : sinisa@bidin.cc
Stability   : experimental

High-level bindings to the @SDL_ttf@ library.

-}

{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveGeneric      #-}
{-# LANGUAGE LambdaCase         #-}
{-# LANGUAGE OverloadedStrings  #-}

module SDL.Font
  (
  -- * General
    initialize
  , version
  , quit

  -- * Loading fonts
  --
  -- | Use the following actions to load @TTF@ and @FON@ file formats.
  , Font(..)
  , PointSize
  , load
  , Index
  , loadIndex
  , decode
  , decodeIndex
  , free

  -- * Rendering text
  --
  -- | Use the following actions to render text to a 'Surface'. The differing
  -- methods available are described in more detail in the original @SDL_ttf@
  -- documentation
  -- <http://www.libsdl.org/projects/SDL_ttf/docs/SDL_ttf.html#SEC42 here>.
  , Color
  , solid
  , shaded
  , blended

  -- * Font attributes
  , Style(..)
  , getStyle
  , setStyle
  , Outline
  , getOutline
  , setOutline
  , Hinting(..)
  , getHinting
  , setHinting
  , Kerning
  , getKerning
  , setKerning
  , height
  , ascent
  , descent
  , lineSkip
  , isMonospace
  , familyName
  , styleName
  ) where

import Control.Monad          (unless)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Bits              ((.&.), (.|.))
import Data.ByteString        (ByteString)
import Data.ByteString.Unsafe (unsafeUseAsCStringLen, unsafePackCString)
import Data.Data              (Data)
import Data.Text              (Text)
import Data.Text.Encoding     (decodeUtf8)
import Data.Text.Foreign      (lengthWord16, unsafeCopyToPtr)
import Data.Typeable          (Typeable)
import Data.Word              (Word8, Word16)
import Foreign.C.String       (CString, withCString)
import Foreign.C.Types        (CUShort, CInt)
import Foreign.Marshal.Alloc  (allocaBytes)
import Foreign.Marshal.Utils  (with, fromBool, toBool)
import Foreign.Ptr            (Ptr, castPtr, nullPtr)
import Foreign.Storable       (peek, pokeByteOff)
import GHC.Generics           (Generic)
import Linear                 (V4(..))
import SDL                    (Surface(..))
import SDL.Exception          (throwIfNull, throwIfNeg_)
import SDL.Raw.Filesystem     (rwFromConstMem)

import qualified SDL.Raw
import qualified SDL.Raw.Font

-- | Gets the major, minor, patch versions of the linked @SDL_ttf@ library.
-- You may call this without initializing the library with 'initialize'.
version :: (Integral a, MonadIO m) => m (a, a, a)
version = liftIO $ do
  SDL.Raw.Version major minor patch <- peek =<< SDL.Raw.Font.getVersion
  return (fromIntegral major, fromIntegral minor, fromIntegral patch)

-- | Initializes the library. Unless noted otherwise, this must be called
-- before any other part of the library is used. You may call this multiple
-- times.
initialize :: MonadIO m => m ()
initialize = do
  init'd <- (== 1) `fmap` SDL.Raw.Font.wasInit
  unless init'd $
    throwIfNeg_ "SDL.Font.initialize" "TTF_Init" SDL.Raw.Font.init

-- | Cleans up any resources still in use by the library. If called, you must
-- call 'initialize' again before using any other parts of the library.
quit :: MonadIO m => m ()
quit = SDL.Raw.Font.quit

-- | Represents a loaded font.
newtype Font = Font { unwrap :: Ptr SDL.Raw.Font.Font }
  deriving (Eq, Typeable)

-- | Point size (based on 72DPI) to load font as. Translates to pixel height.
type PointSize = Int

-- | Given a path to a font file, loads it for use as a 'Font' at a certain
-- 'PointSize'.
load :: MonadIO m => FilePath -> PointSize -> m Font
load path size = do
  fmap Font .
    throwIfNull "SDL.Font.load" "TTF_OpenFont" .
      liftIO . withCString path $
        flip SDL.Raw.Font.openFont $ fromIntegral size

-- | Same as 'load', but accepts a 'ByteString' containing a font instead.
decode :: MonadIO m => ByteString -> PointSize -> m Font
decode bytes size = liftIO $ do
  unsafeUseAsCStringLen bytes $ \(cstr, len) -> do
    rw <- rwFromConstMem (castPtr cstr) (fromIntegral len)
    fmap Font .
      throwIfNull "SDL.Font.decode" "TTF_OpenFontRW" $
        SDL.Raw.Font.openFont_RW rw 0 $ fromIntegral size

-- | Designates a font face, the default and first one being 0.
type Index = Int

-- | Given a path to a font file, loads one of its font faces (designated by
-- the given index) for use as a 'Font' at a certain 'PointSize'. The first
-- face is always index 0, and is the one chosen by default when using 'load'.
loadIndex :: MonadIO m => FilePath -> PointSize -> Index -> m Font
loadIndex path size i = do
  fmap Font .
    throwIfNull "SDL.Font.loadIndex" "TTF_OpenFontIndex" .
      liftIO . withCString path $ \cpath ->
        SDL.Raw.Font.openFontIndex cpath (fromIntegral size) (fromIntegral i)

-- | Same as 'loadIndex', but accepts a 'ByteString' containing a font instead.
decodeIndex :: MonadIO m => ByteString -> PointSize -> Index -> m Font
decodeIndex bytes size i = liftIO $ do
  unsafeUseAsCStringLen bytes $ \(cstr, len) -> do
    rw <- rwFromConstMem (castPtr cstr) (fromIntegral len)
    fmap Font .
      throwIfNull "SDL.Font.decodeIndex" "TTF_OpenFontIndexRW" $
        SDL.Raw.Font.openFontIndex_RW rw 0 (fromIntegral size) (fromIntegral i)

-- | Frees a loaded 'Font'.
free :: MonadIO m => Font -> m ()
free = SDL.Raw.Font.closeFont . unwrap

-- | Color as an RGBA byte vector.
type Color = V4 Word8

-- | Renders 'Text' using the /quick and dirty/ method. Is the fastest of the
-- rendering methods, but results in text that isn't as /smooth/.
solid :: MonadIO m => Font -> Color -> Text -> m SDL.Surface
solid (Font font) (V4 r g b a) text =
  fmap SDL.Surface .
    throwIfNull "SDL.Font.render" "TTF_RenderUNICODE_Solid" .
      liftIO . withText text $ \ptr ->
        with (SDL.Raw.Color r g b a) $ \fg ->
          SDL.Raw.Font.renderUNICODE_Solid font (castPtr ptr) fg

-- | Uses the /slow and nice, but with a solid box/ method. Renders slower than
-- 'solid', but in about the same time as 'blended'. Results in a 'Surface'
-- containing antialiased text of a foreground color surrounded by a box of a
-- background color. This 'Surface' will blit as fast as the one from 'solid'.
shaded :: MonadIO m => Font -> Color -> Color -> Text -> m SDL.Surface
shaded (Font font) (V4 r g b a) (V4 r2 g2 b2 a2) text =
  fmap SDL.Surface .
    throwIfNull "SDL.Font.render" "TTF_RenderUNICODE_Solid" .
      liftIO . withText text $ \ptr -> do
        with (SDL.Raw.Color r g b a) $ \fg ->
          with (SDL.Raw.Color r2 g2 b2 a2) $ \bg ->
            SDL.Raw.Font.renderUNICODE_Shaded font (castPtr ptr) fg bg

-- | The /slow slow slow, but ultra nice over another image/ method, 'blended'
-- renders text at high quality. The text is antialiased and surrounded by a
-- transparent box. Renders slower than 'solid', but in about the same time as
-- 'shaded'. The resulting 'Surface' will blit slower than the ones from
-- 'solid' or 'shaded'.
blended :: MonadIO m => Font -> Color -> Text -> m SDL.Surface
blended (Font font) (V4 r g b a) text =
  fmap SDL.Surface .
    throwIfNull "SDL.Font.render" "TTF_RenderUNICODE_Blended" .
      liftIO . withText text $ \ptr -> do
        with (SDL.Raw.Color r g b a) $ \fg ->
          SDL.Raw.Font.renderUNICODE_Blended font (castPtr ptr) fg

-- Analogous to Data.Text.Foreign.useAsPtr, just appends a null-byte.
-- FIXME: Is this even necessary?
withText :: Text -> (Ptr Word16 -> IO a) -> IO a
withText text act =
  allocaBytes len $ \ptr -> do
    unsafeCopyToPtr text ptr
    pokeByteOff ptr (len - 2) (0 :: CUShort)
    act ptr
  where
    len = 2*(lengthWord16 text + 1)

-- Helper function for converting a bitmask into a list of values.
fromMaskWith :: (Enum a, Bounded a) => (a -> CInt) -> CInt -> [a]
fromMaskWith convert cint = concatMap (\a -> find (a, convert a)) $ [minBound..]
  where
    find (a, i) = if i == i .&. cint then [a] else []

-- Helper function for converting a list of values into a bitmask.
toMaskWith :: (a -> CInt) -> [a] -> CInt
toMaskWith convert = foldr (.|.) 0 . map convert

-- | Possible styles that can be applied to a 'Font'.
data Style
  = Bold
  | Italic
  | Underline
  | Strikethrough
  deriving (Eq, Enum, Ord, Bounded, Data, Generic, Typeable, Read, Show)

styleToCInt :: Style -> CInt
styleToCInt =
  \case
    Bold          -> SDL.Raw.Font.TTF_STYLE_BOLD
    Italic        -> SDL.Raw.Font.TTF_STYLE_ITALIC
    Underline     -> SDL.Raw.Font.TTF_STYLE_UNDERLINE
    Strikethrough -> SDL.Raw.Font.TTF_STYLE_STRIKETHROUGH

-- | Gets the rendering styles of a given 'Font'. If none were ever set, this
-- will be an empty list.
getStyle :: MonadIO m => Font -> m [Style]
getStyle = fmap (fromMaskWith styleToCInt) . SDL.Raw.Font.getFontStyle . unwrap

-- | Sets the rendering style of a 'Font'. Use an empty list to reset the style.
setStyle :: MonadIO m => Font -> [Style] -> m ()
setStyle (Font font) = SDL.Raw.Font.setFontStyle font . toMaskWith styleToCInt

-- | The size of the 'Font' outline, in pixels. Use 0 to turn off outlining.
type Outline = Int

-- | Gets the current outline size of a given 'Font'.
getOutline :: MonadIO m => Font -> m Outline
getOutline = fmap fromIntegral . SDL.Raw.Font.getFontOutline . unwrap

-- | Sets the outline size for a given 'Font'. Use 0 to turn off outlining.
setOutline :: MonadIO m => Font -> Outline -> m ()
setOutline (Font font) = SDL.Raw.Font.setFontOutline font . fromIntegral

-- | The hinting setting of a 'Font'.
data Hinting
  = Normal
  | Light
  | Mono
  | None
  deriving (Eq, Enum, Ord, Bounded, Data, Generic, Typeable, Read, Show)

hintingToCInt :: Hinting -> CInt
hintingToCInt =
  \case
    Normal -> SDL.Raw.Font.TTF_HINTING_NORMAL
    Light  -> SDL.Raw.Font.TTF_HINTING_LIGHT
    Mono   -> SDL.Raw.Font.TTF_HINTING_MONO
    None   -> SDL.Raw.Font.TTF_HINTING_NONE

cIntToHinting :: CInt -> Hinting
cIntToHinting =
  \case
    SDL.Raw.Font.TTF_HINTING_NORMAL -> Normal
    SDL.Raw.Font.TTF_HINTING_LIGHT  -> Light
    SDL.Raw.Font.TTF_HINTING_MONO   -> Mono
    SDL.Raw.Font.TTF_HINTING_NONE   -> None
    _ -> error "SDL.Font.cIntToHinting received unknown TTF_HINTING."

-- | Gets the hinting setting of a given 'Font'.
getHinting :: MonadIO m => Font -> m Hinting
getHinting = fmap cIntToHinting . SDL.Raw.Font.getFontHinting . unwrap

-- | Sets the rendering styles of a font. Use an empty list to reset the style.
setHinting :: MonadIO m => Font -> Hinting -> m ()
setHinting (Font font) = SDL.Raw.Font.setFontHinting font . hintingToCInt

-- | Whether kerning is enabled or not. The default for a newly-loaded 'Font'
-- is enabled.
type Kerning = Bool

-- | Gets the current kerning setting of a given 'Font'.
getKerning :: MonadIO m => Font -> m Kerning
getKerning = fmap toBool . SDL.Raw.Font.getFontKerning . unwrap

-- | Sets the kerning setting for a given 'Font'. Use False to turn off kerning.
setKerning :: MonadIO m => Font -> Kerning -> m ()
setKerning (Font font) = SDL.Raw.Font.setFontKerning font . fromBool

-- | Gets the maximum pixel height of all glyphs of a given 'Font'.
height :: MonadIO m => Font -> m Int
height = fmap fromIntegral . SDL.Raw.Font.fontHeight . unwrap

-- | Gets the maximum pixel ascent of all glyphs of a given 'Font'. This can be
-- interpreted as the distance from the top of the font to the baseline.
ascent :: MonadIO m => Font -> m Int
ascent = fmap fromIntegral . SDL.Raw.Font.fontAscent . unwrap

-- | Gets the maximum pixel descent of all glyphs of a given 'Font'. Also
-- interpreted as the distance from the baseline to the bottom of the font.
descent :: MonadIO m => Font -> m Int
descent = fmap fromIntegral . SDL.Raw.Font.fontDescent . unwrap

-- | Gets the recommended pixel height of a rendered line of text of a given
-- 'Font'. This is usually larger than what 'height' would return.
lineSkip :: MonadIO m => Font -> m Int
lineSkip = fmap fromIntegral . SDL.Raw.Font.fontLineSkip . unwrap

-- | Tests whether the current face of a 'Font' is a fixed width font or not.
isMonospace :: MonadIO m => Font -> m Bool
isMonospace = fmap toBool . SDL.Raw.Font.fontFaceIsFixedWidth . unwrap

cStringToText :: MonadIO m => CString -> m Text
cStringToText = fmap decodeUtf8 . liftIO . unsafePackCString

onlyIfM :: Monad m => Bool -> m a -> m (Maybe a)
onlyIfM = \case
  False -> return . const Nothing
  True  -> fmap Just

-- | Gets the current font face family name, if any.
familyName :: MonadIO m => Font -> m (Maybe Text)
familyName (Font font) = do
  cstr <- SDL.Raw.Font.fontFaceFamilyName font
  onlyIfM (cstr /= nullPtr) $ cStringToText cstr

-- | Gets the current font face style name, if any.
styleName :: MonadIO m => Font -> m (Maybe Text)
styleName (Font font) = do
  cstr <- SDL.Raw.Font.fontFaceStyleName font
  onlyIfM (cstr /= nullPtr) $ cStringToText cstr

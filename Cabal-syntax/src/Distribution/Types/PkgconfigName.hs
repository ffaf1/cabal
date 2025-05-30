{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveGeneric #-}

module Distribution.Types.PkgconfigName
  ( PkgconfigName
  , unPkgconfigName
  , mkPkgconfigName
  ) where

import Distribution.Compat.Prelude
import Distribution.Utils.ShortText
import Prelude ()

import Distribution.Parsec
import Distribution.Pretty

import qualified Distribution.Compat.CharParsing as P
import qualified Text.PrettyPrint as Disp

-- | A pkg-config library name
--
-- This is parsed as any valid argument to the pkg-config utility.
--
-- @since 2.0.0.2
newtype PkgconfigName = PkgconfigName ShortText
  deriving (Generic, Read, Show, Eq, Ord, Data)

-- | Convert 'PkgconfigName' to 'String'
--
-- @since 2.0.0.2
unPkgconfigName :: PkgconfigName -> String
unPkgconfigName (PkgconfigName s) = fromShortText s

-- | Construct a 'PkgconfigName' from a 'String'
--
-- 'mkPkgconfigName' is the inverse to 'unPkgconfigName'
--
-- Note: No validations are performed to ensure that the resulting
-- 'PkgconfigName' is valid
--
-- @since 2.0.0.2
mkPkgconfigName :: String -> PkgconfigName
mkPkgconfigName = PkgconfigName . toShortText

-- | 'mkPkgconfigName'
--
-- @since 2.0.0.2
instance IsString PkgconfigName where
  fromString = mkPkgconfigName

instance Binary PkgconfigName
instance Structured PkgconfigName

-- pkg-config allows versions and other letters in package names, eg
-- "gtk+-2.0" is a valid pkg-config package _name_.  It then has a package
-- version number like 2.10.13
instance Pretty PkgconfigName where
  pretty = Disp.text . unPkgconfigName

instance Parsec PkgconfigName where
  parsec = mkPkgconfigName <$> P.munch1 isNameChar
    where
      -- https://gitlab.haskell.org/ghc/ghc/issues/17752
      isNameChar '-' = True
      isNameChar '_' = True
      isNameChar '.' = True
      isNameChar '+' = True
      isNameChar c = isAlphaNum c

instance NFData PkgconfigName where
  rnf (PkgconfigName pkg) = rnf pkg

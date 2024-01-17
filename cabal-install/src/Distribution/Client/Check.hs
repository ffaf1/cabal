{-# LANGUAGE CPP #-}

-----------------------------------------------------------------------------

-----------------------------------------------------------------------------

-- |
-- Module      :  Distribution.Client.Check
-- Copyright   :  (c) Lennart Kolmodin 2008
-- License     :  BSD-like
--
-- Maintainer  :  kolmodin@haskell.org
-- Stability   :  provisional
-- Portability :  portable
--
-- Check a package for common mistakes
module Distribution.Client.Check
  ( check
  , multiCheck
  ) where

import Distribution.Client.Compat.Prelude
import Prelude ()

import Distribution.Client.Utils.Parsec (renderParseError)
import Distribution.PackageDescription (GenericPackageDescription, PackageName)
import Distribution.PackageDescription.Check
import Distribution.PackageDescription.Parsec
  ( parseGenericPackageDescription
  , runParseResult
  )
import Distribution.Parsec (PWarning (..), showPError)
import Distribution.Simple.Utils (dieWithException, findPackageDesc, notice, warn, warnError)
import System.IO (hPutStr, stderr)

import qualified Control.Monad as CM
import qualified Data.ByteString as BS
import qualified Data.Function as F
import qualified Data.List as L
import qualified Data.List.NonEmpty as NE
import qualified Distribution.Client.Errors as E
import qualified Distribution.Types.PackageName as PN
import qualified System.Directory as Dir

readGenericPackageDescriptionCheck :: Verbosity -> FilePath -> IO ([PWarning], GenericPackageDescription)
readGenericPackageDescriptionCheck verbosity fpath = do
  exists <- Dir.doesFileExist fpath
  unless exists $
    dieWithException verbosity $
      E.FileDoesntExist fpath
  bs <- BS.readFile fpath
  let (warnings, result) = runParseResult (parseGenericPackageDescription bs)
  case result of
    Left (_, errors) -> do
      traverse_ (warn verbosity . showPError fpath) errors
      hPutStr stderr $ renderParseError fpath bs errors warnings
      dieWithException verbosity E.ParseError
    Right x -> return (warnings, x)

-- | Checks a packge for common errors. Returns @True@ if the package
-- is fit to upload to Hackage, @False@ otherwise.
check
  :: Verbosity
  -> Maybe PackageName
  -> [CheckExplanationIDString]
  -- ^ List of check-ids in String form
  -- (e.g. @invalid-path-win@) to ignore.
  -> FilePath
  -- ^ Folder to check (where `.cabal` file is).
  -> IO Bool
check verbosity mPkgName ignores checkDir = do
  epdf <- findPackageDesc checkDir
  pdfile <- case epdf of
    Right cf -> return cf
    Left e -> dieWithException verbosity e
  (ws, ppd) <- readGenericPackageDescriptionCheck verbosity pdfile
  -- convert parse warnings into PackageChecks
  let ws' = map (wrapParseWarning pdfile) ws
  ioChecks <- checkPackageFilesGPD verbosity ppd checkDir
  let packageChecksPrim = ioChecks ++ checkPackage ppd ++ ws'
      (packageChecks, unrecs) = filterPackageChecksByIdString packageChecksPrim ignores

  CM.mapM_ (\s -> warn verbosity ("Unrecognised ignore \"" ++ s ++ "\"")) unrecs
  case mPkgName of
    (Just pn) -> notice verbosity $ "***  " ++ PN.unPackageName pn
    Nothing -> return ()

  CM.mapM_ (outputGroupCheck verbosity) (groupChecks packageChecks)

  let errors = filter isHackageDistError packageChecks

  unless (null errors) $
    warnError verbosity "Hackage would reject this package."

  when (null packageChecks) $
    notice verbosity "No errors or warnings could be found in the package."

  return (null errors)

-- | Same as 'check', but with output adjusted for multiple targets.
multiCheck
  :: Verbosity
  -> [CheckExplanationIDString]
  -- ^ List of check-ids in String form
  -- (e.g. @invalid-path-win@) to ignore.
  -> [(PackageName, FilePath)]
  -- ^ Folder to check (where `.cabal` file is).
  -> IO Bool
multiCheck verbosity _ [] = do
  notice verbosity "check: no targets, nothing to do."
  return True
multiCheck verbosity ignores [(_, checkDir)] = do
  -- Only one target, do not print header with package name.
  check verbosity Nothing ignores checkDir
multiCheck verbosity ignores namesDirs = do
  bs <- CM.mapM (uncurry checkFun) namesDirs
  return (and bs)
  where
    checkFun :: PackageName -> FilePath -> IO Bool
    checkFun mpn wdir = do
      check verbosity (Just mpn) ignores wdir

-------------------------------------------------------------------------------
-- Grouping/displaying checks

-- Poor man’s “group checks by constructor”.
groupChecks :: [PackageCheck] -> [NE.NonEmpty PackageCheck]
groupChecks ds =
  NE.groupBy
    (F.on (==) constInt)
    (L.sortBy (F.on compare constInt) ds)
  where
    constInt :: PackageCheck -> Int
    constInt (PackageBuildImpossible{}) = 0
    constInt (PackageBuildWarning{}) = 1
    constInt (PackageDistSuspicious{}) = 2
    constInt (PackageDistSuspiciousWarn{}) = 3
    constInt (PackageDistInexcusable{}) = 4

groupExplanation :: PackageCheck -> String
groupExplanation (PackageBuildImpossible{}) = "The package will not build sanely due to these errors:"
groupExplanation (PackageBuildWarning{}) = "The following errors are likely to affect your build negatively:"
groupExplanation (PackageDistSuspicious{}) = "These warnings will likely cause trouble when distributing the package:"
groupExplanation (PackageDistSuspiciousWarn{}) = "These warnings may cause trouble when distributing the package:"
groupExplanation (PackageDistInexcusable{}) = "The following errors will cause portability problems on other environments:"

groupOutputFunction :: PackageCheck -> Verbosity -> String -> IO ()
groupOutputFunction (PackageBuildImpossible{}) ver = warnError ver
groupOutputFunction (PackageBuildWarning{}) ver = warnError ver
groupOutputFunction (PackageDistSuspicious{}) ver = warn ver
groupOutputFunction (PackageDistSuspiciousWarn{}) ver = warn ver
groupOutputFunction (PackageDistInexcusable{}) ver = warnError ver

outputGroupCheck :: Verbosity -> NE.NonEmpty PackageCheck -> IO ()
outputGroupCheck ver pcs = do
  let hp = NE.head pcs
      outf = groupOutputFunction hp ver
  notice ver (groupExplanation hp)
  CM.mapM_ (outf . ppPackageCheck) pcs

{-# LANGUAGE ScopedTypeVariables #-}

module Storage
  ( DB
  , listEntries
  , get
  , add
  , del
  , showdbent
  , makeDB
  , openDB
  , writeDB
  ) where

import Control.DeepSeq
import Data.List
import GHC.IO.Exception
import Prompts
import Selection
import System.IO
import System.Process
import System.Posix.IO

type Key = String

-- (service, username, password)
type DBent = (String, String, String)
type DB = [DBent]

showdbent :: DBent -> String
showdbent (s, u, p) =
  concat ["Service:  ", s, "\nUsername: ", u, "\nPassword: ", p]

writeDB :: Key -> DB -> FilePath -> IO ()
writeDB key db dblocat =
  do (x, y) <- createPipe
     h <- fdToHandle y
     outHandle <- openFile dblocat WriteMode
     let cp = CreateProcess
           { cmdspec = RawCommand "openssl" ["enc", "-aes-256-cbc", "-pass",
                                             "fd:" ++ show x]
           , cwd = Nothing
           , env = Just []
           , std_in = CreatePipe
           , std_out = UseHandle outHandle
           , std_err = Inherit
           , close_fds = False
           , create_group = False }
     (Just i, Nothing, Nothing, p) <- createProcess cp
     hPutStrLn i $ show db
     hClose i
     hPutStr h $ key ++ "\n"
     hClose h
     ec <- waitForProcess p
     case ec of
       ExitSuccess -> hClose outHandle
       ExitFailure _ -> error "Fatal error: openssl died."

openDB :: Key -> FilePath -> IO (Maybe DB)
openDB key dblocat =
  do (x, y) <- createPipe
     h <- fdToHandle y
     inHandle <- openFile dblocat ReadMode
     let cp = CreateProcess
           { cmdspec = RawCommand "openssl" ["enc", "-d", "-aes-256-cbc",
                                             "-pass", "fd:" ++ show x]
           , cwd = Nothing
           , env = Just []
           , std_in = UseHandle inHandle
           , std_out = CreatePipe
           , std_err = Inherit
           , close_fds = False
           , create_group = False }
     (Nothing, Just o, Nothing, p) <- createProcess cp
     hPutStr h $ key ++ "\n"
     hClose h
     ec <- waitForProcess p
     hClose inHandle
     case ec of
       ExitSuccess -> do dbStr <- hGetContents o
                         deepseq dbStr $ hClose o
                         return $ Just $ read dbStr
       ExitFailure 1 -> do hClose o
                           return Nothing
       ExitFailure _ -> error "Fatal error: openssl died."

listEntries :: DB -> IO String
listEntries db =
  do let db' = intercalate "\n" $ map (\(x,_,_) -> x) db
     return db'

-- TODO: Prompt the user when multiple options are available.
-- | Returns a DB entry with the specified service/username combination. If
-- neither are specified, prompts the user for the service. Returns $Just e$ if
-- a single entry @e@ was found; if no or multiple entries were found, returns
-- @Nothing@.
get :: DB
       -> Maybe String  -- ^ Selector command
       -> Maybe String  -- ^ Service
       -> Maybe String  -- ^ Username
       -> IO (Maybe DBent)
get [] _ _ _ = return Nothing
get db _ (Just service) _ =
  case filter (\(s, _, _) -> s == service) db of
    [ent] -> return $ Just ent
    _ -> return Nothing
get db _ _ (Just username) =
  case filter (\(_, u, _) -> u == username) db of
    [ent] -> return $ Just ent
    _ -> return Nothing
get db sel Nothing Nothing =
  do serv <- select sel selectService (map (\(a,_,_) -> a) db)
     get db sel (Just serv) Nothing

-- the Bool represents sharing
-- by which I mean whether it overwrote
add :: Key -> FilePath -> DB -> String -> String -> String -> IO Bool
add key dblocat db s u p =
  do let (b, db') = partition (\(x,_,_) -> x == s) db
     let newdb = (s, u, p) : db'
     writeDB key newdb dblocat
     return $ length b == 1

del :: Key
       -> FilePath  -- ^ DB location
       -> DB
       -> Maybe String  -- ^ Selector command
       -> Maybe String  -- ^ Service
       -> Maybe String  -- ^ Username
       -> IO Bool
del key dblocat db sel s u =
  do ent <- get db sel s u
     case ent of
       Just e ->
         do let db' = filter (\e' -> e /= e') db
            writeDB key db' dblocat
            return $ length db - length db' > 0
       Nothing -> error "Could not identify entry to delete."

makeDB :: Key -> FilePath -> IO ()
makeDB key dblocat = writeDB key [] dblocat

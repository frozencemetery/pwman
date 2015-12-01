module Selection where

import System.Exit
import System.IO
import System.Process

-- | If no selector command is given, then the options are displayed on stdout
-- and the user is prompted to enter one of them on stdin. If a selector command
-- (such as `dmenu') is given, then the options are sent to selector command by
-- stdin (each on a separate line)
select :: Maybe String  -- ^ Selector command
          -> String  -- ^ Selector prompt
          -> [String]  -- ^ Options to the selector
          -> IO String
select Nothing prompt opts =
  do _ <- mapM putStrLn opts
     putStr $ prompt ++ " "
     hFlush stdout
     getLine
select (Just command) _ opts =
  do let cp = CreateProcess
           { cmdspec = ShellCommand command
           , cwd = Nothing
           , env = Nothing
           , std_in = CreatePipe
           , std_out = CreatePipe
           , std_err = Inherit
           , close_fds = True  -- The process should not need access to any of our
                               -- file descriptors.
           , create_group = False  -- TODO(sjindel): Should we make this true?
           , delegate_ctlc = False
           }
     (Just i, Just o, Nothing, p) <- createProcess cp
     _ <- mapM (hPutStrLn i) opts
     hClose i
     ec <- waitForProcess p
     case ec of
       ExitSuccess -> do r <- hGetLine o
                         hClose o
                         return r
       ExitFailure _ -> error $ "Selector command (" ++ command ++ ") failed."

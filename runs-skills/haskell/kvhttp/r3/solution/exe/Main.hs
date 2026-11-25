{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import KvHttp (app, newStore)
import Network.Wai.Handler.Warp qualified as Warp
import System.Environment (getArgs, getProgName)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)
import Text.Read (readMaybe)

main :: IO ()
main = do
  args <- getArgs
  case args of
    [p] | Just port <- readMaybe p, port > 0, port < 65536 -> serve port
    _ -> do
      name <- getProgName
      hPutStrLn stderr ("usage: " <> name <> " <port>")
      exitFailure

serve :: Int -> IO ()
serve port = do
  store <- newStore
  let settings =
        Warp.setPort port
          . Warp.setHost "127.0.0.1"
          $ Warp.defaultSettings
  Warp.runSettings settings (app store)

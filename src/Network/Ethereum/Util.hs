{-# LANGUAGE OverloadedStrings #-}

module Network.Ethereum.Util where

import           Crypto.Hash (Digest, Keccak_256, hash)
import           Crypto.Secp256k1
import           Data.ByteString.Short (ShortByteString, fromShort, toShort)
import qualified Data.ByteString as B
import qualified Data.ByteString.Base16 as BS16
import           Data.Either.Utils (maybeToEither)
import           Data.Maybe (listToMaybe)
import           Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import           Data.Word8

import           Debug.Trace

-- TODO make this function safe; decode can fail silently and that's no good
bytesDecode :: Text -> B.ByteString
bytesDecode = fst . BS16.decode . T.encodeUtf8

-- toRpcSig
decomposeSig :: Text -> Maybe CompactRecSig
decomposeSig sig
        | T.length sig /= 130 = Nothing
        | otherwise = traceShow sig $ CompactRecSig sigS sigR <$> sigV -- TODO why are r & s switched?
    where sigR = toShort . (\x -> traceShow (BS16.encode x) x) . bytesDecode $ T.take 64 sig
          sigS = toShort . (\x -> traceShow (BS16.encode x) x) . bytesDecode . T.take 64 . T.drop 64 $ sig
          sigV = fmap adjustV . listToMaybe . B.unpack . bytesDecode . T.take 2 . T.drop 128 $ sig
          adjustV x | x < 27    = x
                    | otherwise = x - 27

ecrecover :: Text -> Text -> Either String Text
ecrecover sig message = do
    compactRecSig <- maybeToEither "decompose sig error" $ decomposeSig sig
    recSig <- maybeToEither "importCompactRecSig error" $ importCompactRecSig compactRecSig
    m <- maybeToEither "msg error" . msg . bytesDecode $ message
    pubkey <- maybeToEither "recover error" $ recover recSig m
    -- hash pubkey
    let keyHash = T.pack $ show (hash (B.drop 1 $ exportPubKey False pubkey) :: Digest Keccak_256)
    -- take last 160 bits of pubkey
    let ethAddr = T.drop 24 keyHash
    return $ ethAddr


-- importPublic :: B.ByteString -> B.ByteString
-- importPublic key
--     | B.length key == 64 = key
--     | otherwise


publicToAddress :: Text -> Text
publicToAddress key = T.drop 24 keyHash
    where keyHash = T.pack $ show (hash (T.encodeUtf8 key) :: Digest Keccak_256)

{-
/**
 * Converts a public key to the Ethereum format.
 * @param {Buffer} publicKey
 * @return {Buffer}
 */
exports.importPublic = function (publicKey) {
  publicKey = exports.toBuffer(publicKey)
  if (publicKey.length !== 64) {
    publicKey = secp256k1.publicKeyConvert(publicKey, false).slice(1)
  }
  return publicKey
}


/**
 * Returns the ethereum address of a given public key.
 * Accepts "Ethereum public keys" and SEC1 encoded keys.
 * @param {Buffer} pubKey The two points of an uncompressed key, unless sanitize is enabled
 * @param {Boolean} [sanitize=false] Accept public keys in other formats
 * @return {Buffer}
 */
exports.pubToAddress = exports.publicToAddress = function (pubKey, sanitize) {
  pubKey = exports.toBuffer(pubKey)
  if (sanitize && (pubKey.length !== 64)) {
    pubKey = secp256k1.publicKeyConvert(pubKey, false).slice(1)
  }
  assert(pubKey.length === 64)
  // Only take the lower 160bits of the hash
  return exports.sha3(pubKey).slice(-20)
}

-}

hashPersonalMessage :: Text -> Text
hashPersonalMessage message = T.pack . show $ keccakDigest
    where messageBytes = bytesDecode message
          prefix = T.encodeUtf8 . T.pack $ "\EMEthereum Signed Message:\n" ++ (show $ B.length messageBytes)
          keccakDigest :: Digest Keccak_256
          keccakDigest = hash (prefix `B.append` messageBytes)

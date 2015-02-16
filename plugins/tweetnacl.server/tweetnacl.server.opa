package tweetnacl.server

type TweetNacl.keyPair = {
  uint8array secretKey,
  uint8array publicKey
}

/** Abstraction of Uint8Array. */
type uint8array = external

protected module Uint8Array {

  function length(uint8array array) { %%ServerNacl.uint8array_length%%(array) }
  function repeat(uint8array pattern, int count) { %%ServerNacl.uint8array_repeat%%(pattern, count) }
  function fill(uint8array array, int value) { %%ServerNacl.uint8array_fill%%(array, value) }
  function concat(uint8array array0, uint8array array1) { %%ServerNacl.uint8array_concat%%(array0, array1) }

  function ofInt(int n) { %%ServerNacl.uint8array_of_int%%(n) }

  function ofBinary(binary bin) { %%ServerNacl.binary_to_uint8array%%(bin) }
  function toBinary(uint8array array) { %%ServerNacl.uint8array_to_binary%%(array) }

  function decodeUTF8(string msg) { %%ServerNacl.nacl_util_decodeUTF8%%(msg) }
  function encodeUTF8(uint8array array) { %%ServerNacl.nacl_util_encodeUTF8%%(array) }
  function decodeHex(string msg) { %%ServerNacl.uint8array_decodeHex%%(msg) }
  function encodeHex(uint8array array) { %%ServerNacl.uint8array_encodeHex%%(array) }
  function decodeBase64(string msg) { %%ServerNacl.nacl_util_decodeBase64%%(msg) }
  function encodeBase64(uint8array array) { %%ServerNacl.nacl_util_encodeBase64%%(array) }

} // END UINT8ARRAY

protected module TweetNacl {

  function hash(uint8array msg) { %%ServerNacl.nacl_hash%%(msg) }
  function randomBytes(int length) { %%ServerNacl.nacl_randomBytes%%(length) }
  function verify(uint8array array0, uint8array array1) { %%ServerNacl.nacl_verify%%(array0, array1) }

  /** Implementation of HMAC-SHA512 algorithm. */
  function hmac(uint8array key, uint8array data) { %%ServerNacl.hmac_sha512%%(key, data) }
  /** Implementation of the pbkdf2 algorithm (http://en.wikipedia.org/wiki/PBKDF2). */
  function pbkdf2(pass, salt, c, len) { %%ServerNacl.pbkdf2%%(pass, salt, c, len) }

  hashLength = %%ServerNacl.nacl_hashLength%%()
  hmacLength = %%ServerNacl.nacl_hashLength%%()

  module Sign {

    function keyPair() { %%ServerNacl.nacl_sign_keyPair%%() }
    function sign(uint8array msg, uint8array secretKey) { %%ServerNacl.nacl_sign%%(msg, secretKey) }
    function open(uint8array signature, uint8array publicKey) { %%ServerNacl.nacl_sign_open%%(signature, publicKey) }

  } // END SIGN

  module Box {

    function keyPair() { %%ServerNacl.nacl_box_keyPair%%() }
    function keyPairFromSecretKey(secretKey) { %%ServerNacl.nacl_box_keyPair_fromSecretKey%%(secretKey) }
    function box(message, nonce, theirPublicKey, mySecretKey) { %%ServerNacl.nacl_box%%(message, nonce, theirPublicKey, mySecretKey) }
    function open(box, nonce, theirPublicKey, mySecretKey) { %%ServerNacl.nacl_box_open%%(box, nonce, theirPublicKey, mySecretKey) }
    function before(theirPublicKey, mySecretKey) { %%ServerNacl.nacl_box_before%%(theirPublicKey, mySecretKey) }
    function after(message, nonce, sharedKey) { %%ServerNacl.nacl_box_after%%(message, nonce, sharedKey) }
    function openAfter(box, nonce, sharedKey) { %%ServerNacl.nacl_box_open_after%%(box, nonce, sharedKey) }

    publicKeyLength = %%ServerNacl.nacl_box_publicKeyLength%%()
    secretKeyLength = %%ServerNacl.nacl_box_secretKeyLength%%()
    sharedKeyLength = %%ServerNacl.nacl_box_sharedKeyLength%%()
    nonceLength = %%ServerNacl.nacl_box_nonceLength%%()
    overheadLength = %%ServerNacl.nacl_box_overheadLength%%()

  } // END BOX

  module SecretBox {

    function box(message, nonce, key) { %%ServerNacl.nacl_secretbox%%(message, nonce, key) }
    function open(message, nonce, key) { %%ServerNacl.nacl_secretbox_open%%(message, nonce, key) }

    keyLength = %%ServerNacl.nacl_secretbox_keyLength%%()
    nonceLength = %%ServerNacl.nacl_secretbox_nonceLength%%()
    overheadLength = %%ServerNacl.nacl_secretbox_overheadLength%%()

  } // END SECRETBOX

}

// _ = %%ServerNacl.HMACtest%%()
// _ = %%ServerNacl.PBKDF2test%%()
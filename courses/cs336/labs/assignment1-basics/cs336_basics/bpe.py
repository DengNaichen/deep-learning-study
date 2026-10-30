import regex as re

PAT = r"""'(?:[sdmt]|ll|ve|re)| ?\p{L}+| ?\p{N}+| ?[^\s\p{L}\p{N}]+|\s+(?!\S)|\s+"""

def init_vocab(special_token: list[str]) -> dict[int, bytes]:
    # Special tokens come from the color, and the 256 single bytes are always the same
    # For this function, we basically build the vocabulary at initialization. We just put every single byte in the vocabulary set

    vocab= {} 

    # for 0 to 255
    for i in range(256):
        vocab[i] = bytes([i])

    for j, token in enumerate(special_token):
        vocab[j + 256] = token.encode("utf-8")

    return vocab

"""Space-link Error Detection and Correction (EDAC): CRC32 + Hamming(7,4)."""

from __future__ import annotations

import zlib
from typing import Any


def compute_crc32(payload: bytes) -> str:
    """Return 8-char uppercase hex CRC32 checksum for a byte payload."""
    return f"{zlib.crc32(payload) & 0xFFFFFFFF:08X}"


def _encode_nibble(nibble: int) -> int:
    """Encode a 4-bit nibble (d1,d2,d3,d4) into a 7-bit Hamming(7,4) codeword."""
    d1 = (nibble >> 3) & 1
    d2 = (nibble >> 2) & 1
    d3 = (nibble >> 1) & 1
    d4 = nibble & 1
    p1 = d1 ^ d2 ^ d4
    p2 = d1 ^ d3 ^ d4
    p3 = d2 ^ d3 ^ d4
    # Bit positions 1..7: p1, p2, d1, p3, d2, d3, d4
    return (p1 << 6) | (p2 << 5) | (d1 << 4) | (p3 << 3) | (d2 << 2) | (d3 << 1) | d4


def _decode_codeword(cw: int) -> tuple[int, bool]:
    """Decode a 7-bit Hamming(7,4) codeword, correcting any single-bit flip."""
    b = [(cw >> (6 - i)) & 1 for i in range(7)]  # b[0]=pos1 .. b[6]=pos7
    s1 = b[0] ^ b[2] ^ b[4] ^ b[6]
    s2 = b[1] ^ b[2] ^ b[5] ^ b[6]
    s3 = b[3] ^ b[4] ^ b[5] ^ b[6]
    syndrome = (s3 << 2) | (s2 << 1) | s1
    corrected = False
    if syndrome != 0:
        b[syndrome - 1] ^= 1
        corrected = True
    nibble = (b[2] << 3) | (b[4] << 2) | (b[5] << 1) | b[6]
    return nibble, corrected


def encode_hamming74(data: bytes) -> list[int]:
    """Encode bytes into a list of 7-bit Hamming(7,4) codewords (2 per byte)."""
    codewords: list[int] = []
    for byte in data:
        codewords.append(_encode_nibble((byte >> 4) & 0xF))
        codewords.append(_encode_nibble(byte & 0xF))
    return codewords


def decode_hamming74(codewords: list[int]) -> tuple[bytes, int]:
    """Decode Hamming(7,4) codewords back to bytes; return (bytes, corrected_bits)."""
    if len(codewords) % 2 != 0:
        raise ValueError("Codeword stream length must be even")
    out = bytearray()
    corrected_count = 0
    for i in range(0, len(codewords), 2):
        hi, c1 = _decode_codeword(codewords[i])
        lo, c2 = _decode_codeword(codewords[i + 1])
        corrected_count += int(c1) + int(c2)
        out.append((hi << 4) | lo)
    return bytes(out), corrected_count


def simulate_space_link_transfer(message: str, inject_bit_flips: int = 1) -> dict[str, Any]:
    """Encode message with CRC32 + Hamming(7,4), optionally flip 1 bit per codeword, and recover."""
    raw = message.encode("utf-8")
    tx_crc = compute_crc32(raw)
    codewords = encode_hamming74(raw)

    flipped_indices: list[int] = []
    corrupted = list(codewords)
    for idx in range(min(inject_bit_flips, len(corrupted))):
        # Flip bit 2 in distinct codewords to simulate cosmic-ray SEU bit flips
        corrupted[idx] ^= 1 << (idx % 7)
        flipped_indices.append(idx)

    recovered_bytes, corrected_bits = decode_hamming74(corrupted)
    rx_crc = compute_crc32(recovered_bytes)

    return {
        "original": message,
        "recovered": recovered_bytes.decode("utf-8", errors="replace"),
        "tx_crc32": tx_crc,
        "rx_crc32": rx_crc,
        "crc_match": tx_crc == rx_crc,
        "codewords_sent": len(codewords),
        "injected_bit_flips": len(flipped_indices),
        "corrected_bits": corrected_bits,
        "edac_scheme": "Hamming(7,4) + CRC32",
    }

/* ==========================================================================
 * aes.h  –  AES-128 Engine driver
 * ECB encryption.  Key is written once; plaintext/ciphertext accessed
 * word-by-word via MMIO.  11-cycle pipeline latency in hardware.
 * ========================================================================== */
#ifndef AES_H
#define AES_H

#include "soc_map.h"

/* AES block and key sizes in words (each word = 32 bits) */
#define AES_BLOCK_WORDS 4u
#define AES_KEY_WORDS   4u

/* Write 128-bit key (key[0] = MSW, key[3] = LSW).
 * Sets KEY_VALID flag.  Must be called before the first encrypt. */
static inline void aes_set_key(const uint32_t key[AES_KEY_WORDS])
{
    AES_KEY0 = key[0];
    AES_KEY1 = key[1];
    AES_KEY2 = key[2];
    AES_KEY3 = key[3];
    AES_CTRL = AES_KEY_VALID_BIT;
}

/* Load 128-bit plaintext (pt[0] = MSW, pt[3] = LSW) and start encryption.
 * Assumes aes_set_key() has already been called.
 * Non-blocking: use aes_wait_done() + aes_read_ciphertext() to get result. */
static inline void aes_start_encrypt(const uint32_t pt[AES_BLOCK_WORDS])
{
    AES_DATA_IN0 = pt[0];
    AES_DATA_IN1 = pt[1];
    AES_DATA_IN2 = pt[2];
    AES_DATA_IN3 = pt[3];
    /* Write START=1 and KEY_VALID=1 together */
    AES_CTRL = AES_START_BIT | AES_KEY_VALID_BIT;
}

/* Poll STATUS until DONE is set.
 * Reading STATUS auto-clears DONE (as per hardware design). */
static inline void aes_wait_done(void)
{
    while (!(AES_STATUS & AES_DONE_BIT))
        ;
}

/* Read the 128-bit ciphertext output (ct[0] = MSW, ct[3] = LSW).
 * Call after aes_wait_done(). */
static inline void aes_read_ciphertext(uint32_t ct[AES_BLOCK_WORDS])
{
    ct[0] = AES_DATA_OUT0;
    ct[1] = AES_DATA_OUT1;
    ct[2] = AES_DATA_OUT2;
    ct[3] = AES_DATA_OUT3;
}

/* Convenience: blocking encrypt.
 *   pt  : 4-word plaintext (in-place: MSW first)
 *   ct  : 4-word ciphertext output
 * Key must already be loaded via aes_set_key(). */
static inline void aes_encrypt(const uint32_t pt[AES_BLOCK_WORDS],
                                uint32_t       ct[AES_BLOCK_WORDS])
{
    aes_start_encrypt(pt);
    aes_wait_done();
    aes_read_ciphertext(ct);
}

/* Returns 1 if the AES engine is currently busy. */
static inline int aes_busy(void)
{
    return !!(AES_STATUS & AES_BUSY_BIT);
}

#endif /* AES_H */

// One-off tool: open an EXISTING MPQ (a copy, never the original) and add
// one more file into it, keeping everything already inside untouched.
#include <StormLib.h>
#include <stdio.h>

int main(int argc, char** argv) {
    if (argc != 4) {
        fprintf(stderr, "usage: %s <existing.mpq (copy!)> <internal\\\\path> <local-file>\n", argv[0]);
        return 1;
    }
    const char* mpq_path = argv[1];
    const char* internal_path = argv[2];
    const char* local_file = argv[3];

    HANDLE mpq = NULL;
    if (!SFileOpenArchive(mpq_path, 0, 0, &mpq)) {
        fprintf(stderr, "SFileOpenArchive failed: %u\n", SErrGetLastError());
        return 1;
    }
    if (!SFileAddFileEx(mpq, local_file, internal_path, MPQ_FILE_COMPRESS, MPQ_COMPRESSION_ZLIB, MPQ_COMPRESSION_ZLIB)) {
        fprintf(stderr, "SFileAddFileEx failed: %u\n", SErrGetLastError());
        SFileCloseArchive(mpq);
        return 1;
    }
    SFileCloseArchive(mpq);
    printf("added %s to %s\n", internal_path, mpq_path);
    return 0;
}

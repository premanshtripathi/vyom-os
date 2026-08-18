#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#include <stdbool.h>
// In modern C (C99 and newer), bool is a built-in type or macro (usually provided by <stdbool.h>).

// typedef uint8_t bool;
// #define true 1
// #define false 0


typedef struct{

    //  FAT12 header
    uint8_t BootJumpInstruction[3]; // 3 bytes - jump instruction to boot code
    uint8_t OemIdentifier[8];       // 8 bytes - OEM identifier

    uint16_t BytesPerSector;     // 2 bytes - number of bytes per sector
    uint8_t SectorsPerCluster;   // 1 byte - number of sectors per cluster
    uint16_t ReservedSectors;    // 2 bytes - number of reserved sectors
    uint8_t FatCount;            // 1 byte - number of FATs
    uint16_t DirEntryCount;      // 2 bytes - number of root directory entries
    uint16_t TotalSectors;       // 2 bytes - total number of sectors on the disk (for a 1.44MB floppy disk, this is 2880 sectors)
    uint8_t MediaDescriptorType; // 1 byte - media descriptor type (F0 = 3.5" floppy disk)
    uint16_t SectorsPerFat;      // 2 bytes - number of sectors per FAT
    uint16_t SectorsPerTrack;    // 2 bytes - number of sectors per track
    uint16_t Heads;              // 2 bytes - number of heads
    uint32_t HiddenSectors;      // 4 bytes - number of hidden sectors
    uint32_t LargeSectorCount;   // 4 bytes - large sector count (for disks larger than 32MB)

    // extended boot record
    uint8_t DriveNumber;     // 1 byte - drive number (0x00 = floppy disk, 0x80 = hard disk, useless for floppy disks)
    uint8_t _Reserved;       // 1 byte - reserved (must be 0)
    uint8_t Signature;       // 1 byte - extended boot signature (0x29 = indicates that the next three fields are present)
    uint32_t VolumeId;       // 4 bytes - volume ID (serial number, can be any value)
    uint8_t VolumeLabel[11]; // 11 bytes - volume label (padded with spaces)
    uint8_t SystemId[8];     // 8 bytes - file system type (padded with spaces)

    // ... We don't care about code ...

    // packed attribute ensures that the compiler does not add any padding between the fields of the struct (which is important for reading the boot sector from disk as it is a binary structure with a specific layout and should match the layout of the boot sector on disk exactly)
} __attribute__((packed)) BootSector;

typedef struct{
    uint8_t Name[11];
    uint8_t Attributes;
    uint8_t _Reserved;
    uint8_t CreatedTimeTenths;
    uint16_t CreatedTime;
    uint16_t CreatedDate;
    uint16_t AccessedDate;
    uint16_t FirstClusterHigh;
    uint16_t ModifiedTime;
    uint16_t ModifiedDate;
    uint16_t FirstClusterLow;
    uint32_t Size;

} __attribute__((packed)) DirectoryEntry;

BootSector g_BootSector;
uint8_t *g_Fat = NULL;
DirectoryEntry *g_RootDirectory = NULL;
uint32_t g_RootDirectoryEnd;

bool readBootSector(FILE *disk){
    return fread(&g_BootSector, sizeof(g_BootSector), 1, disk) > 0;
}

bool readSectors(FILE *disk, uint32_t lba, uint32_t count, void *bufferOut){
    bool ok = true;
    ok = ok && (fseek(disk, lba * g_BootSector.BytesPerSector, SEEK_SET) == 0);
    ok = ok && (fread(bufferOut, g_BootSector.BytesPerSector, count, disk) == count);

    return ok;
}

bool readFat(FILE *disk){
    g_Fat = (uint8_t *)malloc(g_BootSector.SectorsPerFat * g_BootSector.BytesPerSector);
    return readSectors(disk, g_BootSector.ReservedSectors, g_BootSector.SectorsPerFat, g_Fat);
}

bool readRootDirectory(FILE *disk){
    uint32_t lba = g_BootSector.ReservedSectors + g_BootSector.SectorsPerFat * g_BootSector.FatCount;
    uint32_t size = sizeof(DirectoryEntry) * g_BootSector.DirEntryCount;
    uint32_t sectors = (size / g_BootSector.BytesPerSector);

    if (size % g_BootSector.BytesPerSector > 0)
        sectors++;

    g_RootDirectoryEnd = lba + sectors;
    g_RootDirectory = (DirectoryEntry *)malloc(sectors * g_BootSector.BytesPerSector);
    // we allocated memory according to number of sectors instead of the size because the "readSectors" function can only read full sectors.

    return readSectors(disk, lba, sectors, g_RootDirectory);
}

DirectoryEntry* findFile(const char* name){
    for(uint32_t i = 0; i < g_BootSector.DirEntryCount; i++){
        if(memcmp(name, g_RootDirectory[i].Name, 11) == 0) {
            return &g_RootDirectory[i];
        }
    }

    return NULL;
}

bool readFile(DirectoryEntry* fileEntry, FILE* disk, uint8_t* outputBuffer){
    bool ok = true;
    uint16_t currentCluster = fileEntry -> FirstClusterLow;

    do{
        uint32_t lba = g_RootDirectoryEnd + (currentCluster - 2) * g_BootSector.SectorsPerCluster;
        ok = ok && readSectors(disk, lba, g_BootSector.SectorsPerCluster, outputBuffer);
        outputBuffer += g_BootSector.SectorsPerCluster * g_BootSector.BytesPerSector;

        // this calculation is done because each entry in the FAT Table is 12 bits wide in FAT12.
        uint32_t fatIndex = currentCluster * 3 / 2;

        // if cluster number is even then we need to take the bottom 12 bits so we are applying bitmask to remove the top bits that we don't need.
        if(currentCluster % 2 == 0) {
            currentCluster = (*(uint16_t*)(g_Fat + fatIndex)) & 0x0FFF;
        }

        // if it is odd then we need to take the upper 12 bits so we shitf the value to the right by 4 bits;
        else {
            currentCluster = (*(uint16_t*) (g_Fat + fatIndex)) >> 4;
        }
    } while(ok && currentCluster < 0x0FF8);

    return ok;
}

int main(int argc, char **argv){

    if (argc < 3){
        printf("Syntax: %s <disk image> <filename>\n", argv[0]);
        return -1;
    }

    FILE *disk = fopen(argv[1], "rb");

    if (!disk) {
        fprintf(stderr, "Cannot open disk image %s!", argv[1]);
        return -1;
    }

    if (!readBootSector(disk)) {
        fprintf(stderr, "Could not read boot sector!\n");
        return -2;
    }

    if (!readFat(disk)) {
        fprintf(stderr, "Coult not reaad FAT!\n");
        free(g_Fat);
        return -3;
    }

    if (!readRootDirectory(disk)) {
        fprintf(stderr, "Coult not reaad FAT!\n");
        free(g_Fat);
        free(g_RootDirectory);
        return -4;
    }

    DirectoryEntry* fileEntry = findFile(argv[2]);
    
    if(!fileEntry) {
        fprintf(stderr, "Coult not find file %s!\n", argv[2]);
        free(g_Fat);
        free(g_RootDirectory);
        return -5;
    }

    // whenever allocating memory, make sure to allocate an extra sector so that we do not accidentally overrite something or get a segmentation fault.
    uint8_t* buffer = (uint8_t*) malloc(fileEntry -> Size + g_BootSector.BytesPerSector);

    if(!readFile(fileEntry, disk, buffer)) {
        fprintf(stderr, "Could not read file %s!\n", argv[2]);
        free(g_Fat);
        free(g_RootDirectory);
        free(buffer);
    }

    for(size_t i = 0; i < fileEntry -> Size; i++){
        if(isprint(buffer[i])) fputc(buffer[i], stdout);
        else if(buffer[i] == '\n') fputc(buffer[i], stdout);
        else printf("<%02x>", buffer[i]);
    }
    printf("\n");

    free(buffer);
    free(g_Fat);
    free(g_RootDirectory);
    return 0;
}
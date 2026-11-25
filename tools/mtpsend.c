#include <libmtp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
/* usage: send <local> <remote name> <parent folder id> */
int main(int argc, char **argv) {
    if (argc != 4) { fprintf(stderr, "usage: send <local> <name> <parent_id>\n"); return 2; }
    struct stat st;
    if (stat(argv[1], &st) != 0) { perror("stat"); return 1; }
    LIBMTP_Init();
    LIBMTP_mtpdevice_t *dev = LIBMTP_Get_First_Device();
    if (!dev) { fprintf(stderr, "no device\n"); return 1; }
    uint32_t parent = (uint32_t)strtoul(argv[3], NULL, 10);
    /* Replace an existing file with the same name in that folder */
    LIBMTP_file_t *files = LIBMTP_Get_Files_And_Folders(dev, dev->storage->id, parent);
    for (LIBMTP_file_t *f = files; f; f = f->next)
        if (f->filename && strcmp(f->filename, argv[2]) == 0) {
            printf("replacing existing %s (id %u)\n", f->filename, f->item_id);
            LIBMTP_Delete_Object(dev, f->item_id);
        }
    LIBMTP_file_t *file = LIBMTP_new_file_t();
    file->filename = strdup(argv[2]);
    file->filesize = st.st_size;
    file->filetype = LIBMTP_FILETYPE_UNKNOWN;
    file->parent_id = parent;
    file->storage_id = dev->storage->id;
    int ret = LIBMTP_Send_File_From_File(dev, argv[1], file, NULL, NULL);
    if (ret != 0) { LIBMTP_Dump_Errorstack(dev); LIBMTP_Clear_Errorstack(dev); fprintf(stderr, "send failed\n"); }
    else printf("sent %s as id %u\n", argv[2], file->item_id);
    LIBMTP_Release_Device(dev);
    return ret != 0;
}

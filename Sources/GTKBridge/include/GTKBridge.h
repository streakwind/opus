#ifndef OPUS_GTK_BRIDGE_H
#define OPUS_GTK_BRIDGE_H
// GTK owns widgets and calls back on its main thread. All strings are borrowed
// for the duration of a call; the bridge copies strings used asynchronously.
typedef void (*OpusEvent)(const char *action, const char *id, const char *title,
                        const char *day, const char *course, int kind, int start, int end, int page);
int opus_run(OpusEvent event);
void opus_begin(const char *title, const char *destination, int can_undo, int can_delete_list, int show_title);
void opus_list(const char *id, const char *name, int selected);
void opus_task(const char *id, const char *title, const char *detail, int done, int progress, int start, int end, int page);
void opus_empty(const char *message);
void opus_error(const char *message);
void opus_editor(const char *id, const char *title, const char *day, const char *course, int kind, int start, int end, int page);
void opus_editor_list(const char *id, const char *name, int selected);
void opus_editor_close(void);
void opus_quit(void);
#endif

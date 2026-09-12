#ifndef OPUS_THEME_H
#define OPUS_THEME_H

#include <gtk/gtk.h>

void opus_theme_load(void);
void opus_theme_apply_appearance(int mode);
char *opus_theme_resource_path(const char *name);

#endif

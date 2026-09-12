#include "OpusTheme.h"
#include <gio/gio.h>

static GtkCssProvider *opus_css_provider = NULL;

static char *find_resource(const char *name) {
    const char *env = g_getenv("OPUS_RESOURCE_DIR");
    if (env && *env) {
        char *path = g_build_filename(env, name, NULL);
        if (g_file_test(path, G_FILE_TEST_IS_REGULAR)) {
            return path;
        }
        g_free(path);
    }

    char *exe = g_file_read_link("/proc/self/exe", NULL);
    if (exe) {
        char *dir = g_path_get_dirname(exe);
        char *candidates[] = {
            g_build_filename(dir, "..", "share", "opus", name, NULL),
            g_build_filename(dir, "..", "Resources", name, NULL),
            g_build_filename(dir, "resources", name, NULL),
            NULL
        };
        g_free(dir);
        g_free(exe);
        for (int i = 0; candidates[i]; i++) {
            if (g_file_test(candidates[i], G_FILE_TEST_IS_REGULAR)) {
                for (int j = i + 1; candidates[j]; j++) {
                    g_free(candidates[j]);
                }
                return candidates[i];
            }
            g_free(candidates[i]);
        }
    }

    const char *source_candidates[] = {
        "Sources/GTKBridge/resources",
        "../Sources/GTKBridge/resources",
        "../../Sources/GTKBridge/resources",
        NULL
    };
    for (int i = 0; source_candidates[i]; i++) {
        char *path = g_build_filename(source_candidates[i], name, NULL);
        if (g_file_test(path, G_FILE_TEST_IS_REGULAR)) {
            return path;
        }
        g_free(path);
    }
    return NULL;
}

char *opus_theme_resource_path(const char *name) {
    return find_resource(name);
}

void opus_theme_load(void) {
    if (opus_css_provider) {
        return;
    }
    opus_css_provider = gtk_css_provider_new();
    char *path = find_resource("opus.css");
    if (path) {
        gtk_css_provider_load_from_path(opus_css_provider, path);
        g_free(path);
    } else {
        g_warning("Opus theme: opus.css not found; using Adwaita defaults");
    }
    gtk_style_context_add_provider_for_display(
        gdk_display_get_default(),
        GTK_STYLE_PROVIDER(opus_css_provider),
        GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
}

void opus_theme_apply_appearance(int mode) {
    GtkSettings *settings = gtk_settings_get_default();
    if (!settings) {
        return;
    }
    if (mode == 0) {
        gtk_settings_reset_property(settings,
                                    "gtk-application-prefer-dark-theme");
    } else if (mode == 1) {
        g_object_set(settings, "gtk-application-prefer-dark-theme", FALSE, NULL);
    } else {
        g_object_set(settings, "gtk-application-prefer-dark-theme", TRUE, NULL);
    }
}

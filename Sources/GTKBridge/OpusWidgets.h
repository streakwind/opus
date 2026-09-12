#ifndef OPUS_WIDGETS_H
#define OPUS_WIDGETS_H

#include "GTKBridge.h"
#include <gtk/gtk.h>

typedef struct {
    GtkWidget *row;
    GtkWidget *start;
    GtkWidget *end;
    GtkWidget *days_box;
    char *id;
} OpusCourseTimeRow;

typedef struct {
    GtkApplication *application;
    GtkWidget *window;
    GtkWidget *overlay;
    GtkWidget *sidebar;
    GtkWidget *heading;
    GtkWidget *title_row;
    GtkWidget *edit_list;
    GtkWidget *delete_list;
    GtkWidget *delete_archive;
    GtkWidget *undo_button;
    GtkWidget *search_entry;
    GtkWidget *error_label;
    GtkWidget *stack;
    GtkWidget *views[4];
    GtkWidget *rows;
    GtkWidget *quick_entry;
    int active_view;

    GtkWidget *calendar_grid;
    GtkWidget *calendar_undated;
    GHashTable *calendar_days;
    int calendar_columns;
    int calendar_index;

    GtkWidget *schedule_columns;
    GHashTable *schedule_days;
    int schedule_period;

    GtkWidget *editor;
    GtkWidget *editor_dim;
    GtkWidget *editor_card;
    GtkWidget *editor_heading;
    GtkWidget *editor_error;
    GtkWidget *editor_body;
    GtkWidget *editor_actions;
    int editor_type;
    char *editor_id;
    char *editor_rule_id;
    int editor_exists;
    int editor_has_rule;
    GPtrArray *editor_course_ids;
    GPtrArray *editor_time_rows;

    GtkWidget *editor_title;
    GtkWidget *editor_list;
    GtkWidget *editor_day;
    GtkWidget *editor_kind;
    GtkWidget *editor_confirmed;
    GtkWidget *editor_notes;
    GtkWidget *editor_start;
    GtkWidget *editor_target;
    GtkWidget *editor_current;
    GtkWidget *editor_progress_box;
    GtkWidget *editor_name;
    GtkWidget *editor_color;
    GtkWidget *editor_times_box;
    GtkWidget *editor_weekday_box;
    GtkWidget *editor_interval;
    GtkWidget *editor_start_date;
    GtkWidget *editor_end_date;
    GtkWidget *editor_enabled;
    GtkWidget *editor_rule_schedule;
    GtkWidget *editor_start_minute;
    GtkWidget *editor_duration;
    GtkWidget *editor_rule_progress_box;
    GtkWidget *editor_schedule_box;
    GtkWidget *editor_repeat_enabled;
    GtkWidget *editor_repeat_end;
    GtkWidget *editor_delete_scope;
    void (*editor_save)(GtkButton *, gpointer);

    GtkWidget *settings_dialog;
    GtkWidget *help_dialog;
    char *export_suggested_name;
    int appearance_mode;
    int help_page;
} OpusBridgeState;

extern OpusBridgeState opus_ui;

void opus_send(const OpusEventPayload *event);
void opus_send_action(const char *action);
void opus_send_id(const char *action, const char *id);

GtkWidget *opus_label(const char *text);
GtkWidget *opus_button(const char *label, const char *icon, const char *action, const char *id);
GtkWidget *opus_field(GtkWidget *box, const char *name, GtkWidget *input);
GtkWidget *opus_color_dot(const char *color, int size);
GtkWidget *opus_scrolled_box(GtkWidget **box_out);
void opus_margins(GtkWidget *widget, int amount);
void opus_clear_box(GtkWidget *box);
void opus_set_identity(GtkWidget *widget, const char *format, const char *id);
void opus_set_accessible_name(GtkWidget *widget, const char *name);
void opus_append_dropdown(GtkWidget *dropdown, GPtrArray *ids, const char *id,
                          const char *name, const char *selected_id, int selected);
const char *opus_dropdown_id(GtkWidget *dropdown, GPtrArray *ids);
char *opus_text_view_text(GtkWidget *view);
char *opus_json_escape(const char *text);
GdkRGBA opus_color(const char *name);

int opus_work_kind_int(const char *kind);
void opus_set_work_kind(GtkWidget *widget, const char *kind);
GtkWidget *opus_spin_int(int value, int min, int max);
GtkWidget *opus_text_entry(const char *text);
GtkWidget *opus_notes_view(const char *text);
GtkWidget *opus_kind_dropdown(int kind);
GtkWidget *opus_color_dropdown(const char *selected);
const char *opus_color_dropdown_name(GtkWidget *dropdown);
GtkWidget *opus_weekday_box(int selected_mask);
int opus_weekday_mask(GtkWidget *box);
void opus_editor_window_begin(const char *title, int type);
void opus_editor_add_actions(GtkWidget *box, const char *save_action,
                             const char *delete_action);
void opus_editors_close(gboolean notify);

void opus_views_reset(int view);

#endif

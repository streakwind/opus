#ifndef OPUS_GTK_BRIDGE_H
#define OPUS_GTK_BRIDGE_H

typedef struct {
    const char *action;
    const char *id;
    const char *text;
    const char *day;
    const char *course;
    const char *payload;
    int kind;
    int start;
    int end;
    int page;
    int flags;
    int value;
    double y0;
    double y1;
} OpusEventPayload;

typedef void (*OpusEventFn)(const OpusEventPayload *event);

int opus_run(OpusEventFn event);
void opus_quit(void);

void opus_shell_begin(const char *heading, const char *placeholder, int can_undo, int can_delete_list, int show_title, int view, int can_delete_archive);
void opus_nav(const char *id, const char *name, int selected, const char *color, int separator_before);
void opus_section(const char *title);
void opus_work_row(const char *id, const char *kind, const char *title, const char *detail, int done, int progress, int start, int end, int page, int confirmed, const char *color);
void opus_empty(const char *message);
void opus_error(const char *message);

void opus_calendar_begin(const char *heading, int period, int columns);
void opus_calendar_day(const char *day, const char *label, int in_month, int is_today, int selected);
void opus_calendar_item(const char *day, const char *id, const char *kind, const char *title, int done, int confirmed, const char *color);
void opus_calendar_undated(const char *id, const char *kind, const char *title, const char *detail, const char *color);

void opus_schedule_begin(const char *heading, int period, int day_count);
void opus_schedule_day(const char *day, const char *label);
void opus_schedule_block(const char *id, const char *title, const char *detail, const char *day, int start, int duration, int column, int columns, const char *color, int is_class);

void opus_rhythm_row(const char *id, const char *title, const char *detail, int enabled, const char *color);

void opus_work_editor_open(const char *id, const char *title, const char *day, const char *course, int kind, int confirmed, const char *notes, int start, int end, int page);
void opus_work_editor_list(const char *id, const char *name, int selected);
void opus_course_editor_open(const char *id, const char *name, const char *color, int list_only);
void opus_course_editor_time(const char *id, int start, int end, const char *days_csv);
void opus_rule_editor_open(const char *id, const char *title, const char *course, int work_kind, const char *days_csv, int interval, const char *start_day, const char *end_day, int enabled, int confirmed, const char *notes, int start, int target, int start_minute, int duration, int schedule);
void opus_rule_editor_list(const char *id, const char *name, int selected);
void opus_schedule_editor_open(const char *id, const char *title, const char *course, const char *day, int start, int duration, const char *notes, int exists, int has_rule, const char *repeat_end, const char *rule_id);
void opus_schedule_editor_list(const char *id, const char *name, int selected);
void opus_editor_close(void);

void opus_confirm_archive(const char *message);
void opus_settings_open(int appearance);
void opus_help_open(void);
void opus_set_appearance(int mode);
void opus_export_save(const char *suggested_name);
void opus_reveal_path(const char *path);

#endif

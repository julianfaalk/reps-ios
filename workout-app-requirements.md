# Personal Workout App — Requirements Specification

## Project Overview

A personal iOS workout app for iPhone 15 Pro, built natively with Swift/SwiftUI. The app enables live workout tracking, customizable weekly schedules, progress visualization, and local SQLite data storage with export capabilities.

**Target User**: Single user (personal use)  
**Platform**: iOS 17.0+  
**Device**: iPhone 15 Pro  
**Tech Stack**: Swift, SwiftUI, SQLite  

---

## 1. Exercise Library

### 1.1 Exercise Entity

Each exercise stores:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| id | UUID | Yes | Unique identifier |
| name | String | Yes | Exercise name |
| exerciseType | String | Yes | "reps" or "timed" (determines input mode) |
| muscleGroups | [String] | No | Targeted muscles (e.g., "Chest", "Triceps") |
| equipment | String | No | Equipment needed (e.g., "Barbell", "Dumbbells") |
| notes | String | No | Instructions or form cues |
| createdAt | Date | Yes | Timestamp |
| updatedAt | Date | Yes | Timestamp |

**Exercise Types**:
- `reps`: Log sets as reps × weight (e.g., bench press, squats)
- `timed`: Log sets as duration × optional weight (e.g., plank, wall sit, dead hang)

### 1.2 Exercise Management Features

- **Create**: Add new exercises with all fields
- **Read**: View exercise list with search and filter by muscle group
- **Update**: Edit any exercise field
- **Delete**: Remove exercises (with confirmation)

### 1.3 UI Requirements

- List view with search bar
- Filter chips/buttons for muscle groups
- Tap to view details
- Swipe to delete
- Floating action button or toolbar button to add new

---

## 2. Workout Templates

### 2.1 Template Entity

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| id | UUID | Yes | Unique identifier |
| name | String | Yes | Template name (e.g., "Push Day") |
| exercises | [TemplateExercise] | Yes | Ordered list of exercises |
| createdAt | Date | Yes | Timestamp |
| updatedAt | Date | Yes | Timestamp |

### 2.2 Template Exercise Entity

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| id | UUID | Yes | Unique identifier |
| exerciseId | UUID | Yes | Reference to Exercise |
| order | Int | Yes | Position in template |
| targetSets | Int | No | Suggested number of sets |
| targetReps | Int | No | Suggested reps per set (for rep-based) |
| targetDuration | Int | No | Suggested duration in seconds (for timed) |
| targetWeight | Double | No | Suggested weight (kg) |

### 2.3 Template Management Features

- Create named templates
- Add exercises from library to template
- Reorder exercises (drag and drop)
- Set target sets/reps/weight per exercise
- Edit and delete templates

---

## 3. Weekly Schedule

### 3.1 Schedule Entity

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| id | UUID | Yes | Unique identifier |
| dayOfWeek | Int | Yes | 0 = Sunday, 1 = Monday, ..., 6 = Saturday |
| templateId | UUID | No | Assigned workout template (null = rest day) |
| isRestDay | Bool | Yes | Explicit rest day flag |

### 3.2 Schedule Features

- Weekly calendar view (Mon-Sun or Sun-Sat configurable)
- Tap a day to assign a template or mark as rest day
- Visual distinction between workout days and rest days
- Schedule persists until manually changed
- Quick view of what's planned for the week

---

## 4. Live Workout Tracking

### 4.1 Workout Session Entity

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| id | UUID | Yes | Unique identifier |
| templateId | UUID | No | Template used (null if ad-hoc) |
| startedAt | Date | Yes | Session start time |
| completedAt | Date | No | Session end time |
| duration | Int | No | Total duration in seconds |
| notes | String | No | Journal-style session notes |

### 4.2 Session Set Entity

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| id | UUID | Yes | Unique identifier |
| sessionId | UUID | Yes | Parent session |
| exerciseId | UUID | Yes | Exercise performed |
| setNumber | Int | Yes | Set number for this exercise |
| reps | Int | No | Reps completed (for rep-based exercises) |
| duration | Int | No | Duration in seconds (for timed exercises like planks) |
| weight | Double | No | Weight used (kg), nullable for bodyweight exercises |
| completedAt | Date | Yes | Timestamp |

**Note**: Each set uses either `reps` OR `duration`, not both. At least one must be provided.
- Rep-based exercises (e.g., squats): log reps + weight
- Timed exercises (e.g., planks, wall sits): log duration + optional weight

### 4.3 Live Tracking Features

#### Starting a Session
- Start from scheduled template
- Start from any saved template
- Start ad-hoc (empty session)

#### During Session
- Display current exercise with target sets/reps/weight (or duration for timed exercises)
- Log each set based on exercise type:
  - Rep-based: enter reps and weight
  - Timed: enter duration (with optional running timer) and optional weight
- Mark set as complete
- Auto-advance to next exercise when all sets done
- Skip exercise button
- Add unplanned exercise mid-session (pick from library)
- Reorder remaining exercises if needed

#### Timers
- **Rest Timer**:
  - Starts automatically after completing a set
  - Countdown from configured default (e.g., 90 seconds)
  - Audio/haptic alert when timer ends
  - Tap to dismiss early
  - Global default configurable in Settings
- **Workout Timer**:
  - Starts when session begins
  - Counts up (stopwatch style)
  - Visible throughout session
  - Pauses if app backgrounded (optional setting)

#### Session Notes
- Free-text field accessible during and after workout
- Journal style (e.g., "Felt strong today", "Shoulder slightly tight")

#### Completing Session
- Finish workout button
- Summary screen showing:
  - Total duration
  - Exercises completed
  - Total sets/reps
  - Any new PRs achieved
- Option to add/edit notes before saving

---

## 5. Cardio Tracking

### 5.1 Cardio Session Entity

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| id | UUID | Yes | Unique identifier |
| sessionId | UUID | Yes | Parent workout session |
| cardioType | String | Yes | Type (treadmill, bike, rowing, elliptical, stairmaster, other) |
| duration | Int | Yes | Duration in seconds |
| distance | Double | No | Distance in km |
| calories | Int | No | Calories burned |
| avgHeartRate | Int | No | Average BPM |
| maxHeartRate | Int | No | Maximum BPM |
| incline | Double | No | Average incline % |
| resistance | Int | No | Resistance level |
| notes | String | No | Additional notes |

### 5.2 Cardio UI

- Select cardio type from predefined list
- Input fields for all trackable metrics
- All fields optional except type and duration
- Can be part of a mixed session (strength + cardio)

---

## 6. Body Measurements

### 6.1 Measurement Entry Entity

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| id | UUID | Yes | Unique identifier |
| date | Date | Yes | Measurement date |
| bodyWeight | Double | No | Weight in kg |
| bodyFat | Double | No | Body fat percentage |
| neck | Double | No | Neck circumference (cm) |
| shoulders | Double | No | Shoulder circumference (cm) |
| chest | Double | No | Chest circumference (cm) |
| waist | Double | No | Waist circumference (cm) |
| hips | Double | No | Hip circumference (cm) |
| armLeft | Double | No | Left arm circumference (cm) |
| armRight | Double | No | Right arm circumference (cm) |
| forearmLeft | Double | No | Left forearm circumference (cm) |
| forearmRight | Double | No | Right forearm circumference (cm) |
| thighLeft | Double | No | Left thigh circumference (cm) |
| thighRight | Double | No | Right thigh circumference (cm) |
| calfLeft | Double | No | Left calf circumference (cm) |
| calfRight | Double | No | Right calf circumference (cm) |
| notes | String | No | Additional notes |

### 6.2 Progress Photos

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| id | UUID | Yes | Unique identifier |
| measurementId | UUID | Yes | Linked measurement entry |
| photoData | Data | Yes | Image data |
| photoType | String | No | Front, side, back |
| createdAt | Date | Yes | Timestamp |

### 6.3 Measurement Features

- Log measurements by date
- Not all fields required (log what you want)
- Attach multiple photos per entry
- Take photo with camera or select from library
- View measurement history
- Edit/delete past entries

---

## 7. Workout History

### 7.1 History Features

- Chronological list of all past sessions
- Filter by date range
- Filter by template/workout type
- Search by exercise name
- Tap to view session details

### 7.2 Session Detail View

- Full breakdown of exercises and sets
- Compare to template targets (if applicable)
- View session notes
- Edit any logged data
- Delete session (with confirmation)

### 7.3 Edit Capabilities

- Modify reps/weight for any set
- Add missed sets
- Remove incorrectly logged sets
- Edit session notes
- Change session date/time (for late logging)

---

## 8. Charts & Progress Visualization

### 8.1 Exercise Progress Charts

- Line chart showing weight progression over time
- Select specific exercise from library
- Data points = max weight lifted per session
- Option to show volume (sets × reps × weight)

### 8.2 Body Measurement Charts

- Line charts for each measurement type
- Body weight trend over time
- Individual measurement trends
- Overlay multiple measurements for comparison

### 8.3 Time Range Filters

All charts support:
- Last 7 days
- Last 4 weeks
- Last 3 months
- Last year
- All time
- Custom date range

### 8.4 Personal Records (PRs)

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| id | UUID | Yes | Unique identifier |
| exerciseId | UUID | Yes | Exercise reference |
| weight | Double | Yes | PR weight (kg) |
| reps | Int | Yes | Reps at that weight |
| achievedAt | Date | Yes | When PR was set |
| sessionId | UUID | Yes | Session where PR occurred |

**PR Features**:
- Auto-detect new PRs during workout
- Celebrate with visual feedback (animation/confetti)
- PR history per exercise
- Current PR badge on exercise in library

---

## 9. iOS Widgets

### 9.1 Widget Sizes

#### Small Widget
- **Default**: Next scheduled workout (template name + day)
- **During workout**: Rest timer countdown

#### Medium Widget
- **Default**: Today's workout + next 2-3 days preview
- **During workout**: Rest timer + current exercise + set progress (e.g., "Set 3/4")

#### Large Widget
- **Default**: Full week schedule overview
- **During workout**: Workout timer + rest timer + current exercise + upcoming exercises

### 9.2 Widget Behavior

- Tap widget opens app to relevant screen
- Updates in real-time during active session
- Uses WidgetKit for implementation
- Supports iOS 17 interactive widgets if beneficial

---

## 10. Notifications

### 10.1 Workout Reminders

- Local notifications (no server required)
- Configurable reminder time (e.g., "Remind me at 6:00 AM on workout days")
- Only triggers on days with scheduled workouts
- Notification content: "Time for [Template Name]!"

### 10.2 Rest Timer Alerts

- Haptic feedback when rest timer ends
- Optional sound alert
- Works when app is in background

### 10.3 Settings

- Enable/disable workout reminders
- Set reminder time
- Enable/disable rest timer sounds
- Enable/disable haptics

---

## 11. Data Storage

### 11.1 SQLite Database

**Location**: App's Documents directory (persists across app updates)

**Tables**:
- exercises
- templates
- template_exercises
- schedule
- workout_sessions
- session_sets
- cardio_sessions
- measurements
- progress_photos
- personal_records
- settings

### 11.2 Recommended Library

Use **GRDB.swift** or **SQLite.swift** for database operations.

GRDB.swift recommended for:
- Type-safe Swift integration
- Automatic migration support
- Reactive observation (Combine support)
- Good documentation

### 11.3 Data Integrity

- Foreign key constraints enabled
- Cascading deletes where appropriate
- Timestamps on all records
- UUID primary keys

---

## 12. Data Export

### 12.1 Export Formats

- **CSV**: Separate file per data type
- **JSON**: Full database export, single file
- **Excel (.xlsx)**: Workbook with sheet per data type

### 12.2 Export Options

- Export all data
- Export by date range
- Export specific data types only

### 12.3 Export Location

- Share sheet (AirDrop, Files, email, etc.)
- Save to Files app

---

## 13. Settings

### 13.1 Settings Options

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| defaultRestTime | Int | 90 | Rest timer duration (seconds) |
| workoutReminderEnabled | Bool | false | Enable daily reminders |
| workoutReminderTime | Date | 07:00 | Time for reminders |
| restTimerSound | Bool | true | Play sound when timer ends |
| restTimerHaptic | Bool | true | Haptic when timer ends |
| weekStartsOn | Int | 1 | 0 = Sunday, 1 = Monday |

### 13.2 Settings Screen

- All settings in one screen
- Grouped by category (Timers, Notifications, Data)
- Export data button
- App version info

---

## 14. Units

All units are fixed (no conversion needed):

| Measurement | Unit |
|-------------|------|
| Weight (lifting) | kg |
| Body weight | kg |
| Distance | km |
| Body measurements | cm |
| Duration | seconds (stored), displayed as mm:ss or hh:mm:ss |

---

## 15. Navigation Structure

### 15.1 Tab Bar

1. **Today** — Current/next workout, quick start
2. **Schedule** — Weekly calendar view
3. **Exercises** — Exercise library
4. **Progress** — Charts, measurements, PRs
5. **Settings** — App configuration

### 15.2 Key Flows

**Start Workout**:
Today → Tap "Start Workout" → Live tracking screen

**Create Exercise**:
Exercises → "+" button → Exercise form → Save

**Create Template**:
Schedule → Templates → "+" button → Template editor → Save

**Log Measurements**:
Progress → Measurements tab → "+" button → Measurement form → Save

**View Progress**:
Progress → Select chart type → Select exercise/measurement → View chart

---

## 16. Technical Requirements

### 16.1 iOS Version

- Minimum: iOS 17.0
- Reason: Latest SwiftUI features, interactive widgets

### 16.2 Architecture

Recommended: **MVVM** with SwiftUI

```
App/
├── Models/           # Data structures
├── Views/            # SwiftUI views
├── ViewModels/       # Business logic
├── Services/         # Database, notifications
├── Utilities/        # Extensions, helpers
└── Widgets/          # Widget extension
```

### 16.3 Dependencies

Minimize external dependencies. Suggested:

| Package | Purpose |
|---------|---------|
| GRDB.swift | SQLite database |
| Charts (Swift Charts) | Built into iOS 16+ |

### 16.4 No External Dependencies Needed For

- UI: SwiftUI (built-in)
- Charts: Swift Charts (built-in iOS 16+)
- Notifications: UserNotifications (built-in)
- Widgets: WidgetKit (built-in)
- Photos: PhotosUI (built-in)

---

## 17. Implementation Phases

Suggested development order:

### Phase 1: Foundation
- Xcode project setup
- Data models
- Database layer with GRDB
- Basic navigation shell (tab bar)

### Phase 2: Exercise Library
- CRUD operations for exercises
- List view with search
- Muscle group filtering

### Phase 3: Templates & Schedule
- Template CRUD
- Template exercise management
- Weekly schedule view
- Template assignment

### Phase 4: Live Workout Tracking
- Session management
- Set logging
- Rest timer
- Workout timer
- Mid-session flexibility (skip/add)
- Session notes

### Phase 5: Cardio
- Cardio session logging
- Integration with workout sessions

### Phase 6: Body Tracking
- Measurements logging
- Progress photos
- Photo storage

### Phase 7: History & Editing
- Session history list
- Detail view
- Edit/delete functionality

### Phase 8: Charts & PRs
- Exercise progress charts
- Measurement charts
- Time range filters
- PR detection and display

### Phase 9: Widgets
- Widget extension setup
- Small/medium/large variants
- Live activity for timers (optional)

### Phase 10: Polish
- Notifications
- Data export
- Settings screen
- Error handling
- Edge cases

---

## 18. Database Schema

### SQL Table Definitions

```sql
-- Exercises
CREATE TABLE exercises (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    exercise_type TEXT NOT NULL DEFAULT 'reps',  -- 'reps' or 'timed'
    muscle_groups TEXT, -- JSON array
    equipment TEXT,
    notes TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

-- Templates
CREATE TABLE templates (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

-- Template Exercises (join table)
CREATE TABLE template_exercises (
    id TEXT PRIMARY KEY,
    template_id TEXT NOT NULL,
    exercise_id TEXT NOT NULL,
    sort_order INTEGER NOT NULL,
    target_sets INTEGER,
    target_reps INTEGER,        -- For rep-based exercises
    target_duration INTEGER,    -- For timed exercises (seconds)
    target_weight REAL,
    FOREIGN KEY (template_id) REFERENCES templates(id) ON DELETE CASCADE,
    FOREIGN KEY (exercise_id) REFERENCES exercises(id) ON DELETE CASCADE
);

-- Schedule
CREATE TABLE schedule (
    id TEXT PRIMARY KEY,
    day_of_week INTEGER NOT NULL, -- 0-6
    template_id TEXT,
    is_rest_day INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (template_id) REFERENCES templates(id) ON DELETE SET NULL
);

-- Workout Sessions
CREATE TABLE workout_sessions (
    id TEXT PRIMARY KEY,
    template_id TEXT,
    started_at TEXT NOT NULL,
    completed_at TEXT,
    duration INTEGER,
    notes TEXT,
    FOREIGN KEY (template_id) REFERENCES templates(id) ON DELETE SET NULL
);

-- Session Sets
CREATE TABLE session_sets (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    exercise_id TEXT NOT NULL,
    set_number INTEGER NOT NULL,
    reps INTEGER,              -- For rep-based exercises (nullable)
    duration INTEGER,          -- For timed exercises in seconds (nullable)
    weight REAL,               -- Weight in kg (nullable for bodyweight)
    completed_at TEXT NOT NULL,
    FOREIGN KEY (session_id) REFERENCES workout_sessions(id) ON DELETE CASCADE,
    FOREIGN KEY (exercise_id) REFERENCES exercises(id) ON DELETE CASCADE,
    CHECK (reps IS NOT NULL OR duration IS NOT NULL)  -- At least one must be set
);

-- Cardio Sessions
CREATE TABLE cardio_sessions (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    cardio_type TEXT NOT NULL,
    duration INTEGER NOT NULL,
    distance REAL,
    calories INTEGER,
    avg_heart_rate INTEGER,
    max_heart_rate INTEGER,
    incline REAL,
    resistance INTEGER,
    notes TEXT,
    FOREIGN KEY (session_id) REFERENCES workout_sessions(id) ON DELETE CASCADE
);

-- Measurements
CREATE TABLE measurements (
    id TEXT PRIMARY KEY,
    date TEXT NOT NULL,
    body_weight REAL,
    body_fat REAL,
    neck REAL,
    shoulders REAL,
    chest REAL,
    waist REAL,
    hips REAL,
    arm_left REAL,
    arm_right REAL,
    forearm_left REAL,
    forearm_right REAL,
    thigh_left REAL,
    thigh_right REAL,
    calf_left REAL,
    calf_right REAL,
    notes TEXT,
    created_at TEXT NOT NULL
);

-- Progress Photos
CREATE TABLE progress_photos (
    id TEXT PRIMARY KEY,
    measurement_id TEXT NOT NULL,
    photo_data BLOB NOT NULL,
    photo_type TEXT,
    created_at TEXT NOT NULL,
    FOREIGN KEY (measurement_id) REFERENCES measurements(id) ON DELETE CASCADE
);

-- Personal Records
CREATE TABLE personal_records (
    id TEXT PRIMARY KEY,
    exercise_id TEXT NOT NULL,
    weight REAL NOT NULL,
    reps INTEGER NOT NULL,
    achieved_at TEXT NOT NULL,
    session_id TEXT NOT NULL,
    FOREIGN KEY (exercise_id) REFERENCES exercises(id) ON DELETE CASCADE,
    FOREIGN KEY (session_id) REFERENCES workout_sessions(id) ON DELETE CASCADE
);

-- Settings
CREATE TABLE settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
```

---

## 19. Open Questions / Future Considerations

Items explicitly out of scope for v1, but noted for future:

- Cloud sync / backup
- Apple Watch companion app
- Apple Health integration
- Social features / sharing
- AI-powered workout suggestions
- Rest day recommendations based on fatigue
- Barcode scanning for gym equipment
- Integration with heart rate monitors

---

## Summary

This document defines a complete personal workout tracking app with:

- **Exercise library** with full CRUD
- **Workout templates** and **weekly scheduling**
- **Live tracking** with rest timer, workout timer, and real-time logging
- **Cardio support** with standard gym machine metrics
- **Body measurements** and **progress photos**
- **History** with full edit capability
- **Charts** for visualizing progress over time
- **Widgets** for quick access during workouts
- **Local notifications** for workout reminders
- **SQLite storage** with export to CSV, JSON, Excel
- **Native Swift/SwiftUI** implementation

Built for personal use on iPhone 15 Pro, iOS 17+.

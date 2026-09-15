@import url('https://refact0r.github.io/system24/build/system24.css');

/* Omarchy colors on system24. Every ramp mixes between the theme's background
   and foreground, so one mapping serves dark and light themes; {{ mode }} only
   sets color-scheme. The discord-system24 hooks fill the font placeholder in
   body with the current Omarchy font. */

:root {
    color-scheme: {{ mode }};
    --colors: on;

    --text-0: {{ background }};
    --text-1: {{ bright_foreground }};
    --text-2: {{ foreground }};
    --text-3: {{ mix foreground background 15% }};
    --text-4: {{ mix foreground background 40% }};
    --text-5: {{ mix foreground background 60% }};

    --bg-1: {{ mix background foreground 15% }};
    --bg-2: {{ mix background foreground 10% }};
    --bg-3: {{ mix background foreground 5% }};
    --bg-4: {{ background }};
    --hover: rgba({{ foreground_rgb }}, 0.08);
    --active: rgba({{ foreground_rgb }}, 0.14);
    --active-2: rgba({{ foreground_rgb }}, 0.20);
    --message-hover: var(--hover);

    --accent-1: {{ mix accent foreground 20% }};
    --accent-2: {{ accent }};
    --accent-3: {{ accent }};
    --accent-4: {{ mix accent background 15% }};
    --accent-5: {{ mix accent background 30% }};
    --accent-new: var(--red-2);

    --online: var(--green-2);
    --dnd: var(--red-2);
    --idle: var(--yellow-2);
    --streaming: var(--purple-2);
    --offline: var(--text-4);

    --border-light: var(--hover);
    --border: var(--active);
    --border-hover: var(--accent-2);
    --button-border: rgba({{ foreground_rgb }}, 0.10);

    --red-1: {{ mix red foreground 20% }};
    --red-2: {{ red }};
    --red-3: {{ mix red background 12% }};
    --red-4: {{ mix red background 24% }};
    --red-5: {{ mix red background 36% }};

    --green-1: {{ mix green foreground 20% }};
    --green-2: {{ green }};
    --green-3: {{ mix green background 12% }};
    --green-4: {{ mix green background 24% }};
    --green-5: {{ mix green background 36% }};

    --blue-1: {{ mix blue foreground 20% }};
    --blue-2: {{ blue }};
    --blue-3: {{ mix blue background 12% }};
    --blue-4: {{ mix blue background 24% }};
    --blue-5: {{ mix blue background 36% }};

    --yellow-1: {{ mix yellow foreground 20% }};
    --yellow-2: {{ yellow }};
    --yellow-3: {{ mix yellow background 12% }};
    --yellow-4: {{ mix yellow background 24% }};
    --yellow-5: {{ mix yellow background 36% }};

    --purple-1: {{ mix magenta foreground 20% }};
    --purple-2: {{ magenta }};
    --purple-3: {{ mix magenta background 12% }};
    --purple-4: {{ mix magenta background 24% }};
    --purple-5: {{ mix magenta background 36% }};
}

body {
    --font: '__OMARCHY_FONT__';
    --code-font: '__OMARCHY_FONT__';
    --remove-pfp-decor: on;
}

export const Notifications = async ({ $ }) => ({
  event: async ({ event }) => {
    if (event.type === "question.asked" || event.type === "permission.asked") {
      await $`notify-send --app-name=opencode "OpenCode needs input" "A session is waiting for your response."`
    }

    if (event.type === "session.idle") {
      await $`notify-send --app-name=opencode "OpenCode finished" "The operation has completed."`
    }
  },
})

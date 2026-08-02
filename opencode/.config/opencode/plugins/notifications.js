export const Notifications = async ({ $, client }) => ({
  event: async ({ event }) => {
    if (event.type === "question.asked" || event.type === "permission.asked") {
      await $`notify-send --app-name=opencode "OpenCode needs input" "A session is waiting for your response."`
    }

    if (
      event.type === "session.status" &&
      event.properties.status.type === "idle"
    ) {
      let result
      try {
        result = await client.session.get({
          path: { id: event.properties.sessionID },
        })
      } catch {
        return
      }

      const session = result?.data
      if (
        result?.error ||
        !session ||
        session.id !== event.properties.sessionID ||
        session.parentID !== undefined
      ) {
        return
      }

      await $`notify-send --app-name=opencode "OpenCode finished" "The operation has completed."`
    }
  },
})

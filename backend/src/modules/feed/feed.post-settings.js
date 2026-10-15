import { AppError } from "../../shared/utils/errors.js";

// Missing settings preserve the behavior of posts created by older clients.
export function assertPostInteractionAllowed(storyStyle, interaction) {
  const key = interaction === "comment" ? "commentsEnabled" : "sharingEnabled";
  if (storyStyle?.postSettings?.[key] === false) {
    throw new AppError(
      interaction === "comment" ? "POST_COMMENTS_DISABLED" : "POST_SHARING_DISABLED",
      { status: 403 }
    );
  }
}

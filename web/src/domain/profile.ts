const emojiSequence = /(?:\p{Emoji_Presentation}|\p{Emoji}\uFE0F(?:\u20E3)?)/u;

function containsEmoji(value: string): boolean {
  return emojiSequence.test(value);
}

export function validateProfileName(value: string): string | undefined {
  if (!value.trim()) {
    return "Enter a profile name.";
  }
  if (containsEmoji(value)) {
    return "Names cannot include emoji.";
  }
  return undefined;
}

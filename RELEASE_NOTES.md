## v1.13.0-beta.3 (build 59) — 2026-10-02

This beta is about channels where people speak one at a time, and about server administration. In those channels you could only speak once; you can now speak as many times as your turn comes, and the app tells you where you stand in the queue.

### Speaking one at a time
Some servers have channels where only one person is heard at a time. You open your microphone, the server puts you in a queue, and it gives you the floor when your turn comes.

- **You can speak more than once in these channels.** Before, your first turn worked, then everything you said afterwards went nowhere, without any warning. It happened in every microphone mode, push-to-talk included.
- **The app tells you when it's your turn.** When the floor comes to you, you hear a sound and "It's your turn to speak". When your turn ends, another sound and "Your turn to speak has ended". While you wait, you hear your position: "You are number 3 in the speaking queue". The official TeamTalk app plays the sounds, but doesn't tell you your position.
- You can turn these announcements off in Preferences > Announcements, under "Speaking turn in a queue".

### Creating and editing channels
- **The channel dialog has everything the official app has.** In addition to what was there before, you can now set:
  - a classroom channel, where only listed people may speak;
  - a channel where only operators hear what is said;
  - a hidden channel;
  - an operator password, which makes anyone joining with it an operator;
  - the delay before the next person in the queue gets the floor;
  - time limits for voice and for media.
- **One thing this app can't do yet**: give or take the floor in a classroom channel. The checkbox says so, and you can manage that list from another client.
- **Editing a channel no longer changes its codec.** A channel using Speex, or with no codec at all, was converted to Opus as soon as you saved it. Changing the topic of a channel with people in it also failed, because the server refuses a codec change while the channel is occupied.

### Server administration
- **Editing an account no longer wipes what the form doesn't show.** Saving an account erased its other settings, including the channels where it is made operator automatically. And if saving failed, the account could disappear entirely while the app still announced it as updated.
- **Errors are shown.** When the server refuses to create, edit or delete an account, you now hear why. "Account updated" and "Account deleted" are only announced when it really worked.
- **An account that has never logged in says "Never".** It used to show a date in 1970, which VoiceOver read as a real date.

### Streaming
- **Streams from a device or an app are encoded at a higher quality on your Mac before they go out.** It costs no extra bandwidth. Thanks to Rocco Fiorentino.

### Known
- We haven't yet tested a turn that ends while you're streaming from a device. If something sounds wrong at that moment, please tell us.

### Download
[ttaccessible-1.13.0-beta.3-59.zip](https://github.com/math65/ttaccessible/releases/download/v1.13.0-beta.3/ttaccessible-1.13.0-beta.3-59.zip)

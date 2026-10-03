# 🚗 Tesla Mac Widget

**See your Tesla on your Mac's desktop, and lock it, cool it or open the trunk with one click.**
No iPhone needed. It talks to your car through Tesla's official API.

![Tesla Mac Widget, medium and large sizes](docs/images/hero.png)

<sub>Shown with the optional Tesla-style icons. Address and map blurred for privacy.</sub>

- 🔋 Battery %, range, charging time left
- 🔒 Locked or unlocked, 🔴 Sentry on or off, 🌡️ inside temperature
- 📍 Street address and a map (large size)
- 🖼️ The official photo of **your** car: right model, color and wheels
- 👆 Buttons: lock/unlock, climate, frunk, trunk, garage (HomeLink)
- 💸 Free to run for normal use (see [Costs](#-costs))

---

## ⏱️ What you need (about 20 minutes)

| | |
|---|---|
| 💻 | A Mac with **macOS 15 (Sequoia) or newer** |
| 🚗 | A Tesla, and the Tesla app on your phone |
| 🍎 | An Apple ID (the free one is fine) |
| 🐙 | A GitHub account (free; the installer helps you make one) |
| 💳 | A payment card for Tesla's developer site. **Ask a grown-up!** You normally pay $0. |

There are **3 parts**: install the app on your Mac, make a "key" on Tesla's website, then connect them.

---

## Part 1 · Install the app 🧰 (5 minutes)

**1. Get Xcode.** Open the **App Store**, search **Xcode**, click **Get**. It's big, so grab a snack 🍪.
Open Xcode once and click **Install** if it asks.

**2. Sign Xcode in with your Apple ID.** In Xcode: **Settings → Accounts → +** → **Apple ID** → sign in.
Then click your name → **Manage Certificates… → + → Apple Development → Done**.

**3. Get Homebrew** (a helper that installs tools). Go to **[brew.sh](https://brew.sh)**, copy the one long line,
open **Terminal** (press ⌘ Space, type `Terminal`, press Return), paste it and press Return.

**4. Download this project and run the installer.** Paste these into Terminal, one at a time:

```bash
git clone https://github.com/CristoXD73/tesla-mac-widget.git ~/tesla-mac-widget
```

```bash
cd ~/tesla-mac-widget && ./install.sh
```

The installer talks you through everything. It:

1. ✅ checks your Mac
2. ✅ finds your Apple developer account
3. ✅ makes your car keys (the secret one never leaves your Mac)
4. ✅ makes your free website on GitHub (Tesla needs it to trust your app). A browser opens so you can log in to GitHub.
5. ❓ asks if you want Tesla's real app icon (optional, see [Tesla's real look](#-teslas-real-look-free-just-for-you))
6. ✅ builds the app
7. ✅ installs it and puts a 🚗 in your menu bar

At the end it shows your website, like `https://yourname.github.io`. **Write it down**, you need it in Part 2.

---

## Part 2 · Make your key on Tesla's website 🔑 (10 minutes)

**1.** Go to **[developer.tesla.com](https://developer.tesla.com)** and sign in with your **Tesla account**.
> Tesla wants two-step login turned on. If it asks, follow its steps to turn on **Multi-Factor Authentication**.

**2.** Click **Create New Application** (it may say *Request App Access*). On the first page, fill in your
name and email, and pick **personal / individual** if it asks. Click **Next**.

**3. Application Details.** Type anything friendly, like this:

![What to type on the Application Details page](docs/images/step-a-application.svg)

<details><summary>📸 What the real page looks like</summary>

![Tesla's Application Details page](docs/images/tesla-1-application-details.png)
</details>

**4. Client Details.** This page is the most important one! Use **your** website from Part 1 instead of `YOURNAME`:

![What to type on the Client Details page](docs/images/step-b-client.svg)

> ⚠️ Copy them **exactly**: `https`, all small letters, and the `/` at the end of the second one.
> If the box has an **Add** or **+** button, click it, or the address won't be saved.

**5. API & Scopes.** Tick the four **vehicle** boxes:

![Which boxes to tick](docs/images/step-c-scopes.svg)

**6. Billing Details.** Add a card (grown-up time 💳):

![Billing page explanation](docs/images/step-d-billing.svg)

**7. Copy your two codes.** Open your new app on developer.tesla.com. You'll see a **Client ID** and a
**Client Secret** (click the 👁 eye to show it). Then, in the menu bar, click 🚗 → **Setup & Status…** →
**Open credentials.env**, paste the codes after the `=` signs, and save with **⌘S**:

![credentials.env example](docs/images/step-e-credentials.svg)

> 🤫 The Client Secret is like a password. Never post it or send it to anyone.

---

## Part 3 · Connect your car 🔌 (3 minutes)

Click 🚗 in the menu bar → **Setup & Status…** and go down the list. Each step turns ✅ when it's done:

![The setup window with every step done](docs/images/setup-window.png)

1. **Reload**: the app reads the codes you just pasted.
2. **Register**: tells Tesla about your website (takes a second, nothing pops up).
3. **Sign In**: Tesla's login page opens in your browser. Log in and press **Allow**.
   If the browser asks to open **Tesla Widget**, say yes.
4. **Pair the key** (needed for the buttons): scan the QR code with your **iPhone camera**, approve in the
   **Tesla app**, then tap your **key card** on the car's middle console when the car asks.
5. **Add the widget**: right-click your desktop → **Edit Widgets** → search **Tesla** → drag the size you like onto the desktop.

**🎉 You did it!** Turn on **Open at Login** in the 🚗 menu so it keeps working after a restart.

---

## 👆 Using it

| Button | What it does |
|---|---|
| 🔒 | Locks or unlocks |
| 🌀 | Turns climate on or off (turns blue when on) |
| Frunk | Opens the front trunk |
| Trunk | Opens or closes the back trunk |
| 📟 | Opens your garage (HomeLink), if your car has it set up |
| Click the car | Opens the Tesla app through **iPhone Mirroring** |

- A tap changes the widget right away. The button dims while the car answers (about 1–3 seconds). If the car says no, it flips back and shows why.
- A sleeping car gets woken up for the button, so that one press can take ~10 seconds.
- **Clicking the car** opens iPhone Mirroring and opens Tesla for you. The first time, macOS asks to let
  **Tesla Widget** use **Accessibility**. Say yes in System Settings, so it can type "Tesla" into your iPhone's search.

The widget comes in **small, medium and large**. Large adds the map and range.

---

## 🎨 Tesla's real look (free, just for you)

This project doesn't include Tesla's logo or icons (they belong to Tesla). You can still get the real
look on **your own Mac** for free. These stay in `~/.tesla-widget/overrides/` and are never uploaded:

| What | How | Cost |
|---|---|---|
| 🚗 **Your car's photo** | Automatic! The app asks Tesla's API for your car's option codes (color, wheels, model), then gets the matching official picture from Tesla's image service. Menu: 🚗 → **Reload Car Image & Icons** to fetch it again. | Free |
| 🟥 **Tesla app icon** | Say **yes** when `./install.sh` asks. It uses Apple's free App Store lookup API (`itunes.apple.com/lookup?bundleId=com.teslamotors.TeslaApp`) to download the Tesla app's icon. | Free |
| 🔘 **Button icons** | Take a screenshot (⌘⇧4) of just the row of five buttons from your Tesla app's widget (lock, fan, frunk, trunk, HomeLink, on a dark background). Then run the command below and click 🚗 → **Reload Car Image & Icons**. | Free |

```bash
swift ~/tesla-mac-widget/tools/slice-icons.swift ~/Desktop/your-screenshot.png
```

Want a different car picture? Save any PNG as `~/.tesla-widget/overrides/car.png` and reload.

---

## 💸 Costs

Tesla charges developers per use, and gives **every account a monthly credit** (about $10).
This widget is built to stay under it:

- Checks the car about every **15 minutes** (every 5 when charging, driving or with climate on)
- **Never wakes your car** by itself (only when you press a button)
- Stops checking while your screen is asleep
- Counts its own usage (🚗 menu shows *"API usage this month"*) and **slows down, then stops**, before reaching the credit

Normal use comes out to a few dollars of the free credit, so **$0** on your card.

## 🔐 Privacy & safety

- Your car data goes straight from Tesla to your Mac. No other servers, no tracking.
- Your **private key** and **Client Secret** stay in `~/.tesla-widget` on your Mac.
- The public key on your website is **meant** to be public (like a padlock anyone can see but only you can open).
- To remove the app's access: in the car go to **Controls → Locks**, delete its key, and/or delete the app on developer.tesla.com.

---

## 🛟 Help! Something's wrong

<details><summary><b>"The 'redirect_uri' supplied is not registered for this 'client_id'"</b></summary>

![redirect_uri error](docs/images/error-redirect-uri.png)

Tesla doesn't have your sign-in address saved. On developer.tesla.com → your app → **Client Details → Edit**:
- **Allowed Redirect URI(s)** must be exactly `https://YOURNAME.github.io/tesla-callback/` (with the `/` at the end). Press **Add/+** if there's a button.
- **OAuth Grant Type** must include **Authorization Code**.

Save, wait a minute, then click **Sign In** again. If your page still looks like this one, it isn't saved yet:

![Client details missing the redirect URI](docs/images/tesla-client-details-example.png)
</details>

<details><summary><b>Register fails: "Root domain … must match registered allowed origin"</b></summary>

**Allowed Origin URL(s)** on developer.tesla.com must be exactly `https://YOURNAME.github.io`: no `/` at the end, no extra words.
</details>

<details><summary><b>The widget looks old or blank after an update</b></summary>

macOS keeps old widgets in memory. Run this in Terminal, or restart your Mac:

```bash
pkill -f TeslaWidgetExtension; killall NotificationCenter
```
</details>

<details><summary><b>Buttons don't do anything</b></summary>

- Is the 🚗 in your menu bar? The app has to be running (turn on **Open at Login**).
- Did you pair the key (Part 3, step 4)? **Check Pairing** in the setup window should turn ✅.
- Look at the message on the widget: it tells you what the car said.
</details>

<details><summary><b>"Install Xcode" or "No Apple developer certificate"</b></summary>

Do Part 1, steps 1 and 2 again. In Xcode → Settings → Accounts, make sure you see your name and an **Apple Development** certificate.
</details>

---

## 🧹 Uninstall

```bash
~/tesla-mac-widget/uninstall.sh
```

## 🛠️ How it works (for the curious)

```
 Tesla servers ──(official Fleet API)──► Tesla Widget app (menu bar) ──► widget on your desktop
                                           │  keeps your login fresh, checks the car,
 your car ◄──(signed commands)── tesla-http-proxy (Tesla's own open-source tool, runs on your Mac)
```

- `App/`: the menu bar app (sign-in, polling, map, car photo, runs the proxy)
- `Widget/`: the desktop widget (small, medium, large) and its buttons
- `Shared/`: code both use, like the Fleet API client
- `install.sh`, `tools/`, `website/`: the installer and helpers

---

<sub>Not made by or affiliated with Tesla, Inc. "Tesla" and the Tesla logo are trademarks of Tesla, Inc.
This project ships no Tesla artwork; it uses Tesla's public API and image service on your behalf.
MIT licensed.</sub>

// Login / welcome: asks for a player name on first launch (shared by iOS,
// Android and web). Visuals follow the "Player Name" screen of the Classical
// design project — serif heading, surface input, filled accent button, and a
// quiet "continue as guest" escape hatch. The name (or the guest choice) is
// persisted through the store, so this screen only ever shows once.

import { el, clear, LABEL_STYLE } from './dom';
import { state, persist } from '../app/store';
import { navigate, Screen } from './router';

export class LoginScreen implements Screen {
  root = el('div');

  mount(): void {
    this.render();
    // Focus after the mount so the fade-in has begun and iOS shows the caret.
    setTimeout(() => this.root.querySelector('input')?.focus(), 350);
  }

  private render(): void {
    clear(this.root);

    const hint = el('p', {
      style: 'margin:0; font-style:italic; font-size:12.5px; color:transparent; min-height:1.4em',
    }, ' ');
    const showHint = (text: string) => {
      hint.textContent = text;
      hint.style.color = 'color-mix(in srgb, var(--color-text) 55%, transparent)';
    };

    const input = el('input', {
      class: 'input', type: 'text', placeholder: 'Enter your name',
      autocomplete: 'name', maxlength: 40, 'aria-label': 'Player name',
      style: 'padding:var(--space-3); font-size:16px; background:var(--color-surface); border-radius:var(--radius-md)',
      oninput: () => {
        hint.style.color = 'transparent';
        button.style.opacity = input.value.trim() ? '1' : '0.55';
      },
      onkeydown: (e: Event) => { if ((e as KeyboardEvent).key === 'Enter') submit(); },
    });

    const button = el('button', {
      class: 'btn btn-block',
      style: 'min-height:48px; padding:var(--space-3); border-radius:var(--radius-md);' +
        'background:var(--color-accent); color:#fdfcfb; border:none;' +
        'font-family:var(--font-body); font-size:15px; font-weight:500; letter-spacing:0.4px;' +
        'box-shadow:var(--shadow-sm); opacity:0.55; transition:background .14s ease, opacity .2s ease, transform .1s ease',
      onpointerdown: () => { if (input.value.trim()) { button.style.background = 'var(--color-accent-600)'; button.style.transform = 'translateY(1px)'; } },
      onpointerup: () => { button.style.background = 'var(--color-accent)'; button.style.transform = 'none'; },
      onpointerleave: () => { button.style.background = 'var(--color-accent)'; button.style.transform = 'none'; },
      onclick: () => submit(),
    }, 'Start playing');

    const submit = () => {
      const name = input.value.trim();
      if (!name) { showHint('Enter a name, or continue as guest.'); return; }
      showHint(`Setting up your board, ${name}…`);
      state.playerName = name;
      state.guest = false;
      void persist.playerName();
      void persist.guest();
      input.blur(); // dismiss the keyboard before leaving, so its scroll compensation unwinds
      navigate('home');
    };

    const asGuest = (e: Event) => {
      e.preventDefault();
      showHint('Starting a guest game…');
      state.playerName = null;
      state.guest = true;
      void persist.playerName();
      void persist.guest();
      input.blur();
      navigate('home');
    };

    this.root.append(el('div', {
      style: 'min-height:100vh; display:flex; flex-direction:column; font-family:var(--font-body); color:var(--color-text);' +
        'width:min(420px, 100vw); margin:0 auto; padding:0 var(--space-6)',
    },
      el('div', { style: 'flex:none; padding-top:clamp(48px, 12vh, 96px); animation:fade-up .5s ease both' },
        el('h1', { style: 'margin:0; font-size:34px; line-height:1.1' }, 'What should we call you?'),
        el('p', { style: 'margin:var(--space-3) 0 0; font-size:15px; line-height:1.6; color:color-mix(in srgb, var(--color-text) 66%, transparent)' },
          'Used on the scoresheet. Stored on this device only.'),
      ),
      el('div', { style: 'flex:none; padding-top:var(--space-8); display:flex; flex-direction:column; gap:var(--space-2); animation:fade-up .5s .08s ease both' },
        el('span', { style: LABEL_STYLE }, 'Player name'),
        input,
        hint,
      ),
      el('div', { style: 'flex:1' }),
      el('div', { style: 'flex:none; display:flex; flex-direction:column; gap:var(--space-4); padding-bottom:var(--space-8); animation:fade-up .5s .16s ease both' },
        button,
        el('div', { style: 'text-align:center' },
          el('a', {
            href: '#', onclick: asGuest,
            style: 'font-size:14px; color:color-mix(in srgb, var(--color-text) 55%, transparent);' +
              'text-decoration:none; border-bottom:1px solid var(--color-divider); padding-bottom:2px',
          }, 'Continue as guest'),
        ),
      ),
    ));
  }
}

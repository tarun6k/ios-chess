import { loadAll, state } from './app/store';
import { controller } from './app/controller';
import { initRouter, registerScreen, navigate } from './ui/router';
import { GameScreen } from './ui/gameScreen';
import { HomeScreen } from './ui/homeScreen';
import { LoginScreen } from './ui/loginScreen';
import { PuzzlesScreen } from './ui/puzzlesScreen';
import { StatsScreen } from './ui/statsScreen';
import { SettingsScreen } from './ui/settingsScreen';

// The play screen keeps one instance so an in-progress game survives navigation.
let gameScreen: GameScreen | null = null;

async function boot(): Promise<void> {
  await loadAll();

  registerScreen('login', () => new LoginScreen());
  registerScreen('home', () => new HomeScreen());
  registerScreen('play', () => {
    if (!gameScreen) gameScreen = new GameScreen();
    return {
      root: gameScreen.root,
      mount: () => gameScreen!.mount(),
      unmount: () => gameScreen!.unmount(),
    };
  });
  registerScreen('puzzles', () => new PuzzlesScreen());
  registerScreen('stats', () => new StatsScreen());
  registerScreen('settings', () => new SettingsScreen());

  const app = document.getElementById('app')!;
  initRouter(app);

  // First launch: ask for a name (or a guest opt-out) before anything else.
  // A stale #login hash after that choice falls through to home.
  if (!state.playerName && !state.guest) {
    navigate('login');
  } else if (location.hash === '#login') {
    navigate('home');
  }

  // Crash-safe resume: if an unfinished game exists, restore it silently so
  // "Play" (and the Home continue card) both land on the exact position.
  if (state.saved && state.saved.uciMoves.length > 0) {
    controller.resume(state.saved);
  } else {
    controller.newGame({ mode: 'ai', playerColor: 0 });
  }
}

void boot();

// debugging hook (harmless in production; used by tests/automation)
(window as any).__chess = { controller, state };

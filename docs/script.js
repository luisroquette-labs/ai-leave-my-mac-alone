export function pressureLevel(value) {
  return value >= 78 ? 'critical' : value >= 75 ? 'warning' : 'normal';
}

export function cleanupValue(start, progress, target = 72) {
  const safeProgress = Math.min(Math.max(progress, 0), 1);
  const eased = 1 - ((1 - safeProgress) ** 3);
  return Math.round((start + ((target - start) * eased)) * 10) / 10;
}

export function rangePosition(value, min = 70, max = 99) {
  return Math.min(Math.max(((value - min) / (max - min)) * 100, 0), 100);
}

export const demoCopy = {
  en: {
    normal: ['NORMAL', 'Just watching.', 'The SSD is below the warning line. Nothing needs to happen.', 'SSD pressure is normal.'],
    alert: ['ALERT 75%', 'Pressure is rising.', 'The icon changes and macOS sends one notification.', 'The SSD needs attention.'],
    cleanup: ['CLEANUP 78%', 'Time to recover space.', 'Autonomous cleanup uses only the safe list of regenerable development files, up to the level you authorized.', 'Cleanup line reached.'],
    limit: ['LIMIT 80%', 'The ceiling is active.', 'Rounds continue, native caches can join, and the menu reports how much is still required to get back under 80%.', '80% ceiling is active.'],
    cleaning: ['AI CLEANUP', 'Pressure is falling.', 'Regenerable caches and builds are being removed. Your code stays.', 'Safe cleanup in progress.'],
    optimized: ['RELIEVED', 'Space recovered.', 'The simulation returned to a healthy target without touching personal files.', 'SSD pressure is back to normal.']
  },
  pt: {
    normal: ['NORMAL', 'Só observando.', 'O SSD está abaixo do limite de alerta. Nenhuma ação é necessária.', 'Pressão do SSD normal.'],
    alert: ['ALERTA 75%', 'A pressão está subindo.', 'O ícone muda e o macOS envia uma única notificação.', 'O SSD precisa de atenção.'],
    cleanup: ['LIMPEZA 78%', 'Hora de recuperar espaço.', 'A limpeza autônoma usa apenas a lista segura de resíduos de desenvolvimento, até o nível que você autorizou.', 'Limite de limpeza alcançado.'],
    limit: ['LIMITE 80%', 'O teto está ativo.', 'As rodadas continuam, caches nativos podem entrar, e o menu informa quanto ainda falta para voltar abaixo de 80%.', 'Teto de 80% ativo.'],
    cleaning: ['LIMPEZA IA', 'A pressão está caindo.', 'Caches e builds regeneráveis estão sendo removidos. O seu código fica.', 'Limpeza segura em andamento.'],
    optimized: ['ALIVIADO', 'Espaço recuperado.', 'A simulação voltou ao alvo saudável sem tocar em arquivos pessoais.', 'Pressão do SSD normalizada.']
  }
};

export const uiMessages = {
  en: {
    autoOn: 'On',
    autoOff: 'Off',
    registering: 'Saving your download…',
    timeout: 'The server took too long to respond. Try again.',
    fallback: 'The download could not be unlocked. Try again.'
  },
  pt: {
    autoOn: 'Ativa',
    autoOff: 'Inativa',
    registering: 'Registrando seu download…',
    timeout: 'O servidor demorou para responder. Tente novamente.',
    fallback: 'Não foi possível liberar o download. Tente novamente.'
  }
};

export const pageCopy = {
  pt: {
    skip: 'Pular para o conteúdo',
    'nav.problem': 'O problema da IA',
    'nav.how': 'Como funciona',
    'nav.levels': 'Níveis',
    'nav.safety': 'Segurança',
    'nav.code': 'Código',
    'nav.download': 'Baixar grátis',
    'hero.eyebrow': 'Feito para Codex, Claude Code e agentes de programação',
    'hero.title': 'Sua IA escreve código.<br><em>E lota o SSD junto.</em>',
    'hero.lede': 'Worktrees, builds, <code>node_modules</code> e caches crescem a cada tarefa. Escolha até onde o AI, Leave My Mac Alone! pode agir sozinho — Seguro, Profundo ou Emergência — ou execute qualquer nível manualmente.',
    'hero.cta': 'Proteger meu SSD',
    'hero.secondary': 'Ver a limpeza em ação ↓',
    'hero.micro': 'Instale uma vez · verifica a cada 5–30 segundos · sem conta · sem telemetria',
    'mock.status': 'Limpeza necessária',
    'mock.used': 'usado',
    'mock.free': 'livres',
    'mock.alert': 'Alerta aos 75%',
    'mock.clean': 'Limpa aos 78%',
    'mock.limit': 'Teto aos 80%',
    'mock.auto': 'Limpeza automática',
    'mock.login': 'Abrir ao iniciar sessão',
    'mock.checked': 'Disco verificado: 91% em uso.',
    'mock.check': 'Verificar agora',
    'mock.cleanNow': 'Limpar agora',
    'anim.relieved': 'Pressão aliviada',
    'anim.done': 'LIMPEZA SEGURA CONCLUÍDA',
    'anim.title': 'LIMPEZA DE ARTEFATOS DE IA',
    'anim.scope': 'Somente arquivos regeneráveis',
    'anim.map': 'MAPEAR',
    'anim.clean': 'LIMPAR',
    'anim.ready': 'PRONTO',
    'hero.caption': 'Interface em inglês do monitor na barra · limpeza autônoma local',
    'metric.alert': 'aviso antes da crise',
    'metric.clean': 'limpeza sem interromper',
    'metric.limit': 'teto do SSD',
    'metric.privacy': 'dados enviados',
    'problem.eyebrow': 'O custo invisível do código com IA',
    'problem.title': 'Agentes trabalham em paralelo.<br><em>Seu SSD paga a conta.</em>',
    'problem.copy': 'Foi esse problema real que criou o AI, Leave My Mac Alone!: Codex e Claude Code aceleram o trabalho, mas cada execução pode deixar worktrees, dependências, builds e caches ocupando dezenas de gigabytes.',
    'problem.card1.title': 'Mais tarefas, mais cópias',
    'problem.card1.copy': 'Sessões paralelas multiplicam branches, worktrees e ambientes temporários sem avisar quanto espaço consumiram.',
    'problem.card2.title': 'O código termina. O peso fica.',
    'problem.card2.copy': '<code>node_modules</code>, <code>.next</code> e caches de npm, Bun, Deno e Homebrew continuam no SSD depois da entrega.',
    'problem.card3.title': 'Limpeza que entende projetos',
    'problem.card3.copy': 'O app verifica Git, processos ativos e uma lista segura antes de remover somente o que pode ser reconstruído.',
    'problem.contrast': '<strong>Categoria diferente:</strong> CCleaner e utilitários genéricos fazem manutenção ampla. O AI, Leave My Mac Alone! foi desenhado para o rastro técnico de agentes de código e protege fontes, projetos ativos e arquivos pessoais.',
    'proof.eyebrow': 'Veja o modo autônomo decidir',
    'proof.title': 'O agente trabalha.<br><em>O espaço volta.</em>',
    'proof.copy': 'Leve a barra até 78% para simular a limpeza. Esta demonstração segue a política do app e não altera o seu Mac. Os gatilhos de disco são 75%, 78% e 80%. Não há gatilho de disco em 90% ou 95%. O alívio de memória é separado: roda quando a RAM livre fica abaixo de 300 MB e o swap chega a 90% ou mais.',
    'console.subtitle': '— controle para IA',
    'console.local': '100% local',
    'console.auto': 'Limpeza autônoma:',
    'gauge.alert': 'ALERTA 75',
    'gauge.clean': 'LIMPAR 78',
    'gauge.used': 'USADO',
    'console.slider': 'Uso simulado do SSD',
    'tick.normal': 'NORMAL',
    'tick.alert': 'ALERTA',
    'tick.clean': 'LIMPAR',
    'tick.limit': '80% LIMITE',
    'console.target': 'ALVO SEGURO',
    'console.recovered': 'espaço recuperado',
    'time.detected': 'Detectado',
    'time.detectedDetail': '78% alcançado',
    'time.mapping': 'Mapeando',
    'time.mappingDetail': 'Lista segura',
    'time.cleaning': 'Limpando',
    'time.cleaningDetail': 'Resíduos de IA',
    'time.relieved': 'Aliviado',
    'time.relievedDetail': 'Pressão reduzida',
    'audit.scope': 'Escopo seguro',
    'audit.caches': 'Caches de ferramentas',
    'audit.modules': '<code>node_modules</code> ignorados',
    'audit.next': 'Builds <code>.next</code>',
    'audit.git': 'Fontes Git protegidas',
    'levels.eyebrow': 'Você define a permissão',
    'levels.title': 'Três níveis.<br><em>Manual ou autônomo.</em>',
    'levels.copy': 'O nível automático funciona como teto. O app nunca escala para um nível que você não autorizou.',
    'levels.safe.title': 'Seguro',
    'levels.safe.copy': 'Caches e builds regeneráveis, com Git e processos verificados. É o padrão automático.',
    'levels.deep.title': 'Profundo',
    'levels.deep.copy': 'Inclui worktrees inativas e temporários reconhecíveis. Pode ser executado agora ou autorizado continuamente.',
    'levels.emergency.title': 'Emergência',
    'levels.emergency.copy': 'Com autorização específica, alcança arquivos do Codex arquivados há sete dias e VMs regeneráveis do Claude sem arquivos abertos.',
    'safety.eyebrow': 'Entende projetos, não só pastas',
    'safety.title': 'Autonomia com uma fronteira clara.',
    'safety.may': 'PODE LIMPAR',
    'safety.mayTitle': 'Dentro da sua permissão',
    'safety.may1': 'Caches, builds e worktrees regeneráveis',
    'safety.may2': 'No nível Emergência: arquivos arquivados com retenção e VMs sem uso',
    'safety.may3': 'Somente após verificação local de processos e caminhos',
    'safety.never': 'NUNCA TOCA',
    'safety.neverTitle': 'Seu trabalho real',
    'safety.never1': 'Documentos, Mesa, Downloads ou bibliotecas de mídia',
    'safety.never2': 'Fontes Git, credenciais, sessões atuais ou discos externos não selecionados',
    'safety.never3': 'Lixeira existente, dados Docker ou projetos ativos',
    'safety.note': 'Nas preferências, escolha Lixeira, exclusão somente do lote do app ou backup em HD externo com SHA-256 antes de apagar do Mac. Itens antigos da Lixeira permanecem intocados. <a href="https://github.com/luisroquette-labs/ai-leave-my-mac-alone/blob/main/Sources/CleanMyMac/SafeCleaner.swift">Inspecionar o código exato →</a>',
    'steps.eyebrow': 'Instale uma vez',
    'steps.title': 'Deixe seus agentes criarem.<br><em>O espaço se administra sozinho.</em>',
    'steps.one.title': 'Ative em um clique',
    'steps.one.copy': 'O percentual fica na barra do macOS e o monitor abre automaticamente com a sessão.',
    'steps.two.title': 'Use sua IA normalmente',
    'steps.two.copy': 'Codex, Claude Code e seus builds continuam trabalhando enquanto o disco é monitorado.',
    'steps.three.title': 'Recupere espaço',
    'steps.three.copy': 'Aos 78%, a lista segura entra em ação. Acima de 80%, uma nova rodada ocorre após 5 minutos quando a anterior liberou espaço; sem progresso, o backoff aumenta a espera até 30 minutos.',
    'demo.eyebrow': 'Aplicativo real',
    'demo.title': 'A demonstração gravada está sendo refeita.',
    'demo.copy': 'O vídeo anterior de 12 segundos mostrava um nome antigo e marcas de disco em 90% e 95%. Esses não são os gatilhos de disco do app. Use a demonstração ao vivo da política acima até a nova gravação em inglês ser publicada.',
    'download.eyebrow': 'Grátis e código aberto',
    'download.title': 'Pare de interromper sua IA para caçar cache.',
    'download.copy': 'Você escolhe o maior nível de autonomia. O app persegue o teto de 80% dentro dessa permissão e avisa quando dados protegidos impedem o resto.',
    'download.help': 'Instruções de instalação →',
    'form.title': 'Para onde enviamos as novidades?',
    'form.privacy': 'Preencha os dados para liberar o download gratuito. A CF Gauss registra o contato no pipeline comercial e poderá falar com você sobre o AI, Leave My Mac Alone!.',
    'form.name': 'Nome',
    'form.whatsapp': 'WhatsApp',
    'form.email': 'E-mail',
    'form.submit': 'Liberar download grátis',
    'ready.title': 'Seu download está pronto.',
    'ready.copy': 'Seu contato foi registrado. O arquivo ZIP contém o aplicativo para macOS.',
    'ready.button': 'Baixar AI, Leave My Mac Alone!',
    footer: 'Proteção de SSD feita para quem constrói com IA. Software independente e aberto por <a href="https://github.com/luisroquette">Luis Roquette</a>, sem afiliação ou endosso da MacPaw.'
  }
};

const hasDocument = typeof document !== 'undefined';
let currentLang = 'en';
let renderDemo = () => {};
const originals = new Map();

function rememberOriginals() {
  document.querySelectorAll('[data-i18n], [data-i18n-html]').forEach(node => {
    originals.set(node, { text: node.textContent, html: node.innerHTML });
  });
}

export function applyLanguage(lang) {
  currentLang = lang === 'pt' ? 'pt' : 'en';
  if (!hasDocument) return currentLang;
  document.documentElement.lang = currentLang === 'pt' ? 'pt-BR' : 'en';
  document.querySelectorAll('[data-i18n]').forEach(node => {
    const key = node.dataset.i18n;
    const original = originals.get(node);
    node.textContent = currentLang === 'pt' && pageCopy.pt[key] != null ? pageCopy.pt[key] : original.text;
  });
  document.querySelectorAll('[data-i18n-html]').forEach(node => {
    const key = node.dataset.i18nHtml;
    const original = originals.get(node);
    node.innerHTML = currentLang === 'pt' && pageCopy.pt[key] != null ? pageCopy.pt[key] : original.html;
  });
  document.querySelectorAll('[data-set-lang]').forEach(button => {
    button.setAttribute('aria-pressed', String(button.dataset.setLang === currentLang));
  });
  const autoClean = document.querySelector('[data-auto-clean]');
  const autoLabel = document.querySelector('[data-auto-label]');
  if (autoClean && autoLabel) {
    const enabled = autoClean.getAttribute('aria-pressed') === 'true';
    autoLabel.textContent = enabled ? uiMessages[currentLang].autoOn : uiMessages[currentLang].autoOff;
  }
  renderDemo();
  try {
    localStorage.setItem('leave-my-mac-alone-lang', currentLang);
  } catch {
    /* private mode */
  }
  const url = new URL(window.location.href);
  if (currentLang === 'pt') url.searchParams.set('lang', 'pt');
  else url.searchParams.delete('lang');
  window.history.replaceState(null, '', url);
  return currentLang;
}

function initialLanguage() {
  const fromQuery = new URLSearchParams(window.location.search).get('lang');
  if (fromQuery === 'pt' || fromQuery === 'en') return fromQuery;
  try {
    const stored = localStorage.getItem('leave-my-mac-alone-lang');
    if (stored === 'pt' || stored === 'en') return stored;
  } catch {
    /* private mode */
  }
  return 'en';
}

const section = hasDocument ? document.querySelector('[data-pressure]') : null;

if (section) {
  const slider = section.querySelector('#storage');
  const autoClean = section.querySelector('[data-auto-clean]');
  const timeline = [...section.querySelectorAll('.cleanup-timeline li')];
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  let cleanupTimer;
  let cleanupFrame;
  let phase = 'idle';
  let lastValue = Number(slider.value);

  function storyFor(value) {
    const pack = demoCopy[currentLang];
    if (phase === 'cleaning') return pack.cleaning;
    if (phase === 'optimized') return pack.optimized;
    if (value >= 80) return pack.limit;
    if (value >= 78) return pack.cleanup;
    if (value >= 75) return pack.alert;
    return pack.normal;
  }

  function setTimeline(activeStep = -1, complete = false) {
    timeline.forEach((item, index) => {
      item.classList.toggle('is-done', complete || index < activeStep);
      item.classList.toggle('is-active', !complete && index === activeStep);
    });
  }

  function render(value, progress = 0) {
    lastValue = value;
    const level = pressureLevel(value);
    const state = storyFor(value);
    const color = level === 'critical' ? '#ce4333' : level === 'warning' ? '#d97724' : '#6f9a76';
    section.dataset.level = level;
    section.dataset.phase = phase;
    section.style.setProperty('--percent', value);
    section.style.setProperty('--gauge-color', color);
    section.style.setProperty('--range-position', `${rangePosition(value)}%`);
    section.querySelector('[data-percent]').textContent = `${Math.round(value)}%`;
    section.querySelector('[data-state]').textContent = state[0];
    section.querySelector('[data-title]').textContent = state[1];
    section.querySelector('[data-copy]').textContent = state[2];
    section.querySelector('[data-gauge-status]').textContent = state[3];

    if (phase === 'cleaning') setTimeline(progress < 0.3 ? 1 : progress < 0.88 ? 2 : 3);
    else if (phase === 'optimized') setTimeline(3, true);
    else setTimeline(level === 'critical' ? 0 : -1);
  }

  renderDemo = () => render(lastValue, phase === 'optimized' ? 1 : 0);

  function stopCleanup() {
    window.clearTimeout(cleanupTimer);
    window.cancelAnimationFrame(cleanupFrame);
  }

  function startCleanup() {
    const start = Number(slider.value);
    if (start < 78 || autoClean.getAttribute('aria-pressed') !== 'true') return;
    phase = 'cleaning';

    if (reducedMotion.matches) {
      slider.value = '72';
      phase = 'optimized';
      render(72, 1);
      return;
    }

    const startedAt = performance.now();
    const duration = 3200;
    const tick = now => {
      const progress = Math.min((now - startedAt) / duration, 1);
      const value = cleanupValue(start, progress);
      slider.value = String(value);
      render(value, progress);
      if (progress < 1) cleanupFrame = window.requestAnimationFrame(tick);
      else {
        phase = 'optimized';
        render(72, 1);
      }
    };
    cleanupFrame = window.requestAnimationFrame(tick);
  }

  function scheduleCleanup() {
    stopCleanup();
    if (Number(slider.value) >= 78 && autoClean.getAttribute('aria-pressed') === 'true') cleanupTimer = window.setTimeout(startCleanup, 800);
  }

  slider.addEventListener('input', () => {
    stopCleanup();
    phase = 'idle';
    render(Number(slider.value));
    scheduleCleanup();
  });

  autoClean.addEventListener('click', () => {
    const enabled = autoClean.getAttribute('aria-pressed') !== 'true';
    autoClean.setAttribute('aria-pressed', String(enabled));
    autoClean.querySelector('[data-auto-label]').textContent = enabled ? uiMessages[currentLang].autoOn : uiMessages[currentLang].autoOff;
    if (enabled) scheduleCleanup();
    else stopCleanup();
  });

  render(Number(slider.value));
}

if (hasDocument) {
  rememberOriginals();
  document.querySelectorAll('[data-set-lang]').forEach(button => {
    button.addEventListener('click', () => applyLanguage(button.dataset.setLang));
  });

  const nav = document.querySelector('[data-nav]');
  const pageProgress = document.querySelector('[data-page-progress]');
  const updateChrome = () => {
    const scrollable = document.documentElement.scrollHeight - window.innerHeight;
    const progress = scrollable > 0 ? window.scrollY / scrollable : 0;
    pageProgress.style.transform = `scaleX(${Math.min(Math.max(progress, 0), 1)})`;
    nav.classList.toggle('is-scrolled', window.scrollY > 24);
  };
  window.addEventListener('scroll', updateChrome, { passive: true });
  updateChrome();

  const leadForm = document.querySelector('[data-lead-form]');
  if (leadForm) {
    const formWrap = document.querySelector('[data-lead-form-wrap]');
    const ready = document.querySelector('[data-download-ready]');
    const downloadLink = document.querySelector('[data-download-link]');
    const status = leadForm.querySelector('[data-form-status]');
    const submit = leadForm.querySelector('button[type="submit"]');

    leadForm.addEventListener('submit', async event => {
      event.preventDefault();
      if (!leadForm.reportValidity() || submit.disabled) return;
      const messages = uiMessages[currentLang];
      submit.disabled = true;
      status.textContent = messages.registering;
      status.dataset.kind = 'pending';
      const controller = new AbortController();
      const requestTimeout = window.setTimeout(() => controller.abort(), 12_000);

      try {
        const fields = new FormData(leadForm);
        const response = await fetch('https://cfgauss.com.br/api/lead/clean-my-mac', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(Object.fromEntries(fields)),
          signal: controller.signal
        });
        const result = await response.json();
        if (!response.ok || !result.success || !result.downloadUrl) throw new Error(result.error || messages.fallback);
        downloadLink.href = result.downloadUrl;
        formWrap.hidden = true;
        ready.hidden = false;
        ready.focus();
      } catch (error) {
        status.textContent = error.name === 'AbortError'
          ? uiMessages[currentLang].timeout
          : error.message || uiMessages[currentLang].fallback;
        status.dataset.kind = 'error';
        submit.disabled = false;
      } finally {
        window.clearTimeout(requestTimeout);
      }
    });
  }

  applyLanguage(initialLanguage());
}

// Optional Claude assistant.
//
// The page is sent as an image, so Claude reads your actual handwriting
// rather than relying on a separate OCR step. Nothing leaves the device
// unless you press Ask, and the key is only ever sent to api.anthropic.com.

const ENDPOINT = 'https://api.anthropic.com/v1/messages';
const API_VERSION = '2023-06-01';

export const MODELS = [
  { id: 'claude-opus-5', name: 'Claude Opus 5', note: 'Most capable' },
  { id: 'claude-sonnet-5', name: 'Claude Sonnet 5', note: 'Faster, cheaper' },
  { id: 'claude-haiku-4-5', name: 'Claude Haiku 4.5', note: 'Fastest' },
];

// Effort is only accepted by the current top-tier models.
const SUPPORTS_EFFORT = new Set(['claude-opus-5', 'claude-sonnet-5']);

const SYSTEM_PROMPT = `You are a study assistant inside a handwriting note-taking app.
You are shown an image of the page the user is currently looking at, plus any
text they typed on it. Read the handwriting carefully. Answer their request
directly and concisely, quoting or referring to what is actually on the page.
If the handwriting is genuinely illegible, say so rather than guessing.`;

/**
 * Ask Claude about the current page.
 * @param {object} opts
 * @param {string} opts.apiKey    Anthropic API key
 * @param {string} opts.model     model id from MODELS
 * @param {string} opts.question  the user's request
 * @param {string} opts.imageBase64  page PNG, base64 without the data: prefix
 * @param {string} [opts.typedText]  any typed text boxes on the page
 */
export async function askClaude({ apiKey, model, question, imageBase64, typedText }) {
  if (!apiKey) throw new Error('Add your Anthropic API key in Settings first.');

  const parts = [];
  if (typedText && typedText.trim()) {
    parts.push(`Typed text on this page:\n${typedText.trim()}`);
  }
  parts.push(`Request: ${question}`);

  const body = {
    model,
    max_tokens: 16000,
    system: SYSTEM_PROMPT,
    messages: [
      {
        role: 'user',
        content: [
          { type: 'image', source: { type: 'base64', media_type: 'image/png', data: imageBase64 } },
          { type: 'text', text: parts.join('\n\n') },
        ],
      },
    ],
  };

  if (SUPPORTS_EFFORT.has(model)) {
    body.output_config = { effort: 'medium' };
  }

  let response;
  try {
    response = await fetch(ENDPOINT, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': API_VERSION,
        // Opt in to calling the API straight from a browser.
        'anthropic-dangerous-direct-browser-access': 'true',
      },
      body: JSON.stringify(body),
    });
  } catch (err) {
    throw new Error('Could not reach Anthropic. Check your connection and try again.');
  }

  if (!response.ok) {
    let detail = `Request failed (HTTP ${response.status}).`;
    try {
      const payload = await response.json();
      if (payload?.error?.message) detail = payload.error.message;
    } catch (_) {
      /* keep the generic message */
    }
    if (response.status === 401) detail = 'That API key was rejected. Check it in Settings.';
    if (response.status === 429) detail = 'Rate limited by the API — wait a moment and try again.';
    throw new Error(detail);
  }

  const data = await response.json();

  if (data.stop_reason === 'refusal') {
    throw new Error('Claude declined to answer this one.');
  }

  const text = (data.content || [])
    .filter((block) => block.type === 'text')
    .map((block) => block.text)
    .join('\n')
    .trim();

  return text || 'No answer came back — try rephrasing the question.';
}

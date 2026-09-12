// Minimal OpenRouter (chat completions) helper for strict-JSON-schema
// generation. Server-side only. Mirrors roundtable/Services/OpenAIClient.swift.

/** Frontier director model. Reasoning is mandatory on fable — capped at "low"
 *  effort (~6 s), hidden behind the client's turn lookahead. */
export const DIRECTOR_MODEL = "anthropic/claude-fable-5.1";
/** Faster model (reasoning disabled) for latency-critical replies to the user. */
export const FAST_MODEL = "anthropic/claude-sonnet-5";

interface ChatEnvelope {
  choices?: Array<{ message?: { content?: string | null } }>;
}

/**
 * Calls OpenRouter with a strict JSON schema and returns the parsed
 * structured output.
 */
export async function structuredResponse<T>(opts: {
  model: string;
  instructions: string;
  input: string;
  schemaName: string;
  schema: Record<string, unknown>;
}): Promise<T> {
  const key = process.env.OPENROUTER_API_KEY;
  if (!key) throw new Error("OPENROUTER_API_KEY is not configured");

  const res = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: opts.model,
      max_tokens: 1200,
      messages: [
        { role: "system", content: opts.instructions },
        { role: "user", content: opts.input },
      ],
      // fable-5.1 can't disable reasoning (cap it low); sonnet-5 can.
      reasoning:
        opts.model === FAST_MODEL ? { enabled: false } : { effort: "low" },
      response_format: {
        type: "json_schema",
        json_schema: {
          name: opts.schemaName,
          strict: true,
          schema: opts.schema,
        },
      },
    }),
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`OpenRouter HTTP ${res.status}: ${body.slice(0, 300)}`);
  }

  const envelope = (await res.json()) as ChatEnvelope;
  const text = envelope.choices?.[0]?.message?.content;
  if (!text) throw new Error("OpenRouter response contained no content");
  return JSON.parse(text) as T;
}

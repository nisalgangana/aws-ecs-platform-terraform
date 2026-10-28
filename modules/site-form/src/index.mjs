// Landing site forms (dealer applications, contact messages) -> SNS -> e-mail.
// Reached only through CloudFront /api/* (function URL uses AWS_IAM; CloudFront signs with OAC).
import { SNSClient, PublishCommand } from "@aws-sdk/client-sns";

const sns = new SNSClient({});
const MAX = 2000;

const clean = (v, max = 200) => (typeof v === "string" ? v.trim().slice(0, max) : "");
const reply = (status, body) => ({
  statusCode: status,
  headers: { "content-type": "application/json", "cache-control": "no-store" },
  body: JSON.stringify(body),
});

export const handler = async (event) => {
  if (event.requestContext?.http?.method !== "POST" || event.rawPath !== "/api/enquiry") {
    return reply(404, { ok: false, error: "Not found." });
  }

  let body;
  try {
    const raw = event.isBase64Encoded
      ? Buffer.from(event.body ?? "", "base64").toString("utf8")
      : event.body ?? "";
    body = JSON.parse(raw);
  } catch {
    return reply(400, { ok: false, error: "Invalid request." });
  }
  if (typeof body !== "object" || body === null) {
    return reply(400, { ok: false, error: "Invalid request." });
  }

  // honeypot: real people never fill this hidden field
  if (clean(body.website)) return reply(200, { ok: true });

  const kind = clean(body.kind) === "dealer" ? "dealer" : "contact";
  const name = clean(body.name, 100);
  const phone = clean(body.phone, 30);
  const email = clean(body.email, 120);

  if (!name) return reply(422, { ok: false, error: "Please enter your name." });
  if (!/^[+\d][\d\s\-()]{6,}$/.test(phone)) {
    return reply(422, { ok: false, error: "Please enter a valid phone number." });
  }
  if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return reply(422, { ok: false, error: "That email address doesn't look right." });
  }

  const entry = {
    kind, name, phone, email,
    district: clean(body.district),
    role: clean(body.role),
    topic: clean(body.topic),
    from: clean(body.from),
    to: clean(body.to),
    size: clean(body.size),
    message: clean(body.message, MAX),
    receivedAt: new Date().toISOString(),
  };
  const text = Object.entries(entry)
    .filter(([, v]) => v)
    .map(([k, v]) => `${k}: ${v}`)
    .join("\n");

  try {
    await sns.send(new PublishCommand({
      TopicArn: process.env.TOPIC_ARN,
      // SNS subjects must be plain ASCII: no customer name here
      Subject: kind === "dealer" ? "Acme: new dealer application" : "Acme: new contact message",
      Message: text,
    }));
  } catch (err) {
    console.error("[enquiry] publish failed", err?.name); // no personal data in logs
    return reply(500, { ok: false, error: "Something went wrong. Please try again." });
  }

  console.log("[enquiry] sent", kind);
  return reply(200, { ok: true });
};

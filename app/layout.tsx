import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'Avanis v1',
  description: 'Avanis v1 — deployed with GitHub Actions',
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}

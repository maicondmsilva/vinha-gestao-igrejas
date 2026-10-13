const unavailableDatabase = new Proxy(
  {},
  {
    get() {
      throw new Error(
        'Esta rota ainda depende do banco legado e não está disponível no ambiente Vercel.',
      );
    },
  },
);

export const env = new Proxy<Record<string, unknown>>(
  {},
  {
    get(_target, property) {
      if (property === 'DB') return unavailableDatabase;
      return process.env[String(property)];
    },
  },
);

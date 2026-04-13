import { useState, useEffect, useCallback } from 'react';

function currentPath() {
  const h = window.location.hash || '#/';
  return h.startsWith('#') ? h.slice(1) : h;
}

export function useHashRoute() {
  const [path, setPath] = useState(currentPath());
  useEffect(() => {
    const onChange = () => setPath(currentPath());
    window.addEventListener('hashchange', onChange);
    return () => window.removeEventListener('hashchange', onChange);
  }, []);
  const navigate = useCallback((to) => {
    window.location.hash = to.startsWith('/') ? to : `/${to}`;
  }, []);
  return { path, navigate };
}

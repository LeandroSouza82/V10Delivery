React Dashboard — instruções rápidas para remover motos offline em tempo real

Objetivo
- Garantir que, quando um motorista fizer logout no app Flutter (ou seu campo `esta_online` for ajustado no Supabase), o marcador (moto) suma do mapa instantaneamente sem recarregar a página.

Sugestão de implementação (React + Supabase Realtime)

1) Mantenha uma lista de motoristas no estado do componente `Dashboard`:

```js
const [motoristas, setMotoristas] = useState([]);
```

2) Sempre filtre antes de renderizar os marcadores:

```js
const exibiveis = motoristas.filter(m => m.esta_online === true && m.status === 'online');
```

3) Assine eventos Realtime do Supabase para a tabela `motoristas`:

```js
useEffect(() => {
  const subscription = supabase
    .channel('public:motoristas')
    .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'motoristas' }, payload => {
      const updated = payload.new;
      setMotoristas(prev => {
        // replace or insert
        const idx = prev.findIndex(m => m.id === updated.id);
        if (idx === -1) return [...prev, updated];
        const copy = [...prev];
        copy[idx] = updated;
        return copy;
      });
    })
    .subscribe();

  // cleanup
  return () => {
    supabase.removeChannel(subscription);
  };
}, []);
```

4) Renderize marcadores baseados em `exibiveis`:

```jsx
{exibiveis.map(m => (
  <Marker key={m.id} position={[m.lat, m.lng]} /* ... */ />
))}
```

Observações
- O filtro é restritivo: filtra por `esta_online === true && status === 'online'` para garantir que, se qualquer um dos campos indicar offline, o motorista suma.
- Garanta que a sua aplicação React atualize `motoristas` com os dados iniciais (fetch ao montar) e assine eventos Realtime como acima.
- Se a sua UI usa um mapa (Leaflet/Mapbox), atualize apenas a lista de marcadores; isso garante remoção instantânea sem reload.

Se quiser, posso gerar o patch React com a integração Realtime se me fornecer o caminho do componente `Dashboard` no repositório.
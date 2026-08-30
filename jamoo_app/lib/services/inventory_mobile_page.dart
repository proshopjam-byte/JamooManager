const String inventoryMobilePageHtml = r'''<!doctype html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
  <meta name="theme-color" content="#386641">
  <title>JamooManager 在庫・販売</title>
  <style>
    :root{color-scheme:light;--green:#386641;--green2:#6a994e;--pale:#f3f8ef;--card:#fff;--line:#d8e2d2;--red:#b3261e;--redbg:#ffdad6;--text:#1f2a1f;--muted:#647064}
    *{box-sizing:border-box}body{margin:0;background:var(--pale);color:var(--text);font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","Noto Sans JP",sans-serif}
    button,input,select,textarea{font:inherit}button{cursor:pointer}.hidden{display:none!important}
    header{position:sticky;top:0;z-index:5;background:#edf5e8eF;backdrop-filter:blur(10px);border-bottom:1px solid var(--line);padding:12px 14px}
    .head{max-width:900px;margin:auto;display:flex;align-items:center;gap:10px}.title{font-weight:800;font-size:19px;flex:1}.facility{font-size:12px;color:var(--muted)}
    main{max-width:900px;margin:auto;padding:14px 14px 90px}.search{display:flex;gap:8px;margin-bottom:12px}.search input{flex:1}
    input,select,textarea{width:100%;border:1px solid #849181;background:white;border-radius:11px;padding:12px;color:var(--text)}
    .btn{border:0;border-radius:999px;padding:10px 15px;background:var(--green);color:white;font-weight:700;white-space:nowrap}.btn.light{background:#dcefd7;color:#24512e}.btn.outline{background:white;color:var(--green);border:1px solid var(--green)}.btn.danger{background:var(--redbg);color:var(--red)}
    .summary{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;margin-bottom:14px}.sum{background:#e2e8df;border-radius:14px;padding:12px}.sum small{display:block;color:var(--muted)}.sum strong{font-size:21px}
    .items{display:grid;gap:10px}.item{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:14px;box-shadow:0 1px 2px #0000000b}.item.low{border-color:#e7a7a1}
    .item-top{display:flex;gap:10px;align-items:flex-start}.item-name{font-size:17px;font-weight:800;flex:1}.category{font-size:12px;color:var(--muted);margin-top:2px}.stock{text-align:right}.stock strong{display:block;font-size:22px}.low .stock strong{color:var(--red)}
    .prices{display:flex;gap:16px;color:var(--muted);font-size:13px;margin:10px 0}.actions{display:flex;gap:7px;flex-wrap:wrap}.actions .btn{flex:1;min-width:90px;padding:9px 10px}
    .empty{text-align:center;background:white;border:1px solid var(--line);padding:32px;border-radius:16px;color:var(--muted)}
    .overlay{position:fixed;inset:0;z-index:20;background:#17201799;display:flex;align-items:flex-end;justify-content:center}.panel{width:100%;max-width:600px;max-height:92vh;overflow:auto;background:var(--pale);border-radius:22px 22px 0 0;padding:20px}.panel h2{margin:0 0 14px}.field{margin:12px 0}.field label{display:block;font-size:13px;font-weight:700;margin:0 0 5px}.panel-actions{display:flex;gap:8px;justify-content:flex-end;margin-top:18px}.panel-actions .btn{min-width:110px}
    .login{align-items:center}.login .panel{border-radius:22px;max-width:420px}.code{font-size:24px;letter-spacing:5px;text-align:center;font-weight:800}.help{font-size:13px;color:var(--muted);line-height:1.6}
    .toast{position:fixed;left:50%;bottom:22px;z-index:40;transform:translateX(-50%);background:#243124;color:white;padding:11px 18px;border-radius:999px;box-shadow:0 4px 18px #0003;max-width:90%;text-align:center}
    .error{background:var(--redbg);color:var(--red);border-radius:11px;padding:10px;margin:10px 0}.spinner{padding:35px;text-align:center;color:var(--muted)}
    @media(max-width:560px){.summary{grid-template-columns:repeat(2,1fr)}.sum:last-child{grid-column:span 2}.prices{gap:10px}.actions .btn{min-width:72px}.facility{display:none}}
  </style>
</head>
<body>
  <header><div class="head"><div><div class="title">在庫・販売</div><div id="facility" class="facility">JamooManager</div></div><button id="reload" class="btn light">更新</button><button id="logout" class="btn outline">コード再入力</button></div></header>
  <main>
    <div class="search"><input id="search" inputmode="search" placeholder="商品名・コード・バーコードで検索"><button id="clear" class="btn light">クリア</button></div>
    <div class="summary"><div class="sum"><small>登録商品</small><strong id="itemCount">0件</strong></div><div class="sum"><small>在庫不足</small><strong id="lowCount">0件</strong></div><div class="sum"><small>表示中</small><strong id="shownCount">0件</strong></div></div>
    <div id="content" class="spinner">接続しています…</div>
  </main>

  <div id="login" class="overlay login hidden"><div class="panel"><h2>接続コード</h2><p class="help">Windows版JamooManagerの「端末接続」に表示された8桁のコードを入力してください。</p><input id="token" class="code" inputmode="numeric" maxlength="8" autocomplete="one-time-code" placeholder="00000000"><div id="loginError" class="error hidden"></div><div class="panel-actions"><button id="connect" class="btn">接続</button></div></div></div>

  <div id="movement" class="overlay hidden"><div class="panel"><h2 id="movementTitle">入出庫・販売</h2><div id="movementStock" class="help"></div><div class="field"><label for="type">処理</label><select id="type"><option value="sale">販売</option><option value="purchase">入荷</option><option value="internal_use">館内使用</option><option value="waste">廃棄</option><option value="return_to_stock">返品・在庫戻し</option><option value="adjustment">棚卸調整</option></select></div><div class="field"><label id="quantityLabel" for="quantity">数量</label><input id="quantity" inputmode="decimal" value="1"></div><div class="field"><label for="price">単価（円・任意）</label><input id="price" inputmode="numeric"></div><div class="field"><label for="note">備考（任意）</label><textarea id="note" rows="2"></textarea></div><div id="movementError" class="error hidden"></div><div class="panel-actions"><button id="cancelMovement" class="btn outline">キャンセル</button><button id="saveMovement" class="btn">記録</button></div></div></div>

  <div id="toast" class="toast hidden"></div>
  <script>
    const state={token:localStorage.getItem('jamoo_inventory_token')||'',items:[],selected:null,loading:false};
    const el=id=>document.getElementById(id);
    const escapeHtml=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
    const qty=value=>Number.isInteger(Number(value))?String(Number(value)):Number(value).toFixed(3).replace(/\.?0+$/,'');
    const yen=value=>value==null?'－':'¥'+Number(value).toLocaleString('ja-JP');
    const uuid=()=>globalThis.crypto?.randomUUID?.()||'mobile-'+Date.now()+'-'+Math.random().toString(16).slice(2);

    async function api(path,options={}){
      const headers={'X-Jamoo-Token':state.token,...(options.headers||{})};
      if(options.body)headers['Content-Type']='application/json';
      const response=await fetch(path,{...options,headers});
      let data={};try{data=await response.json()}catch(_){data={error:'応答を読み込めませんでした。'}}
      if(response.status===401){showLogin('接続コードを確認してください。');throw new Error(data.error||'認証できませんでした。')}
      if(!response.ok)throw new Error(data.error||'処理に失敗しました。');return data;
    }
    function showLogin(message=''){el('loginError').textContent=message;el('loginError').classList.toggle('hidden',!message);el('login').classList.remove('hidden');setTimeout(()=>el('token').focus(),50)}
    function hideLogin(){el('login').classList.add('hidden');el('loginError').classList.add('hidden')}
    function toast(message){el('toast').textContent=message;el('toast').classList.remove('hidden');setTimeout(()=>el('toast').classList.add('hidden'),2400)}
    async function connect(){const token=el('token').value.trim();if(!/^\d{8}$/.test(token)){showLogin('8桁の数字を入力してください。');return}state.token=token;try{const health=await api('/api/v1/health');localStorage.setItem('jamoo_inventory_token',token);el('facility').textContent=health.facilityName||'JamooManager';hideLogin();await loadItems()}catch(error){showLogin(error.message)}}
    async function loadItems(silent=false){if(state.loading||!state.token)return;state.loading=true;if(!silent){el('content').className='spinner';el('content').textContent='読み込み中…'}try{const health=await api('/api/v1/health');el('facility').textContent=health.facilityName||'JamooManager';const data=await api('/api/v1/inventory/items');state.items=data.items||[];render()}catch(error){if(!state.token)return;if(!silent||!state.items.length){el('content').className='error';el('content').textContent='接続が切れています。Windows版で「端末接続」を開き、この画面を更新してください。'}}finally{state.loading=false}}
    function render(){const term=el('search').value.trim().toLowerCase();const items=state.items.filter(item=>[item.name,item.category,item.sku,item.barcode].some(value=>String(value||'').toLowerCase().includes(term)));el('itemCount').textContent=state.items.length+'件';el('lowCount').textContent=state.items.filter(item=>Number(item.currentStock)<=Number(item.reorderLevel)).length+'件';el('shownCount').textContent=items.length+'件';if(!items.length){el('content').className='empty';el('content').textContent='該当する商品がありません。';return}el('content').className='items';el('content').innerHTML=items.map(item=>{const low=Number(item.currentStock)<=Number(item.reorderLevel);return `<article class="item ${low?'low':''}"><div class="item-top"><div class="item-name">${escapeHtml(item.name)}<div class="category">${escapeHtml(item.category)}${item.barcode?' ・ '+escapeHtml(item.barcode):''}</div></div><div class="stock"><strong>${qty(item.currentStock)} ${escapeHtml(item.unit)}</strong><small>最低 ${qty(item.reorderLevel)} ${escapeHtml(item.unit)}</small></div></div><div class="prices"><span>販売 ${yen(item.salePriceYen)}</span><span>仕入 ${yen(item.costPriceYen)}</span></div><div class="actions">${item.saleEnabled?`<button class="btn" data-key="${escapeHtml(item.syncKey)}" data-type="sale">販売</button>`:''}<button class="btn light" data-key="${escapeHtml(item.syncKey)}" data-type="purchase">入荷</button><button class="btn light" data-key="${escapeHtml(item.syncKey)}" data-type="internal_use">館内使用</button><button class="btn outline" data-key="${escapeHtml(item.syncKey)}" data-type="more">その他</button></div></article>`}).join('')}
    function openMovement(key,type){const item=state.items.find(value=>value.syncKey===key);if(!item)return;state.selected=item;el('movementTitle').textContent=item.name;el('movementStock').textContent='現在庫：'+qty(item.currentStock)+' '+item.unit;el('type').value=type==='more'?'waste':type;el('quantity').value='1';el('note').value='';applyType();el('movementError').classList.add('hidden');el('movement').classList.remove('hidden')}
    function applyType(){const item=state.selected;const type=el('type').value;el('quantityLabel').textContent=type==='adjustment'?'調整後の実在庫':'数量';el('price').value=type==='sale'?(item?.salePriceYen??''):type==='purchase'?(item?.costPriceYen??''):''}
    async function saveMovement(){const item=state.selected;const quantity=Number(el('quantity').value);if(!item||!Number.isFinite(quantity)||quantity<0){el('movementError').textContent='数量を確認してください。';el('movementError').classList.remove('hidden');return}const button=el('saveMovement');button.disabled=true;try{const priceText=el('price').value.trim();const result=await api('/api/v1/inventory/movements',{method:'POST',body:JSON.stringify({itemIdentifier:item.syncKey,transactionUuid:uuid(),type:el('type').value,quantity,unitPriceYen:priceText===''?null:Number(priceText),note:el('note').value.trim()||null,deviceId:navigator.userAgent.includes('CrOS')?'chromebook':'mobile',occurredAt:new Date().toISOString()})});el('movement').classList.add('hidden');toast(result.itemName+' ・ 在庫 '+qty(result.stockAfter));await loadItems()}catch(error){el('movementError').textContent=error.message;el('movementError').classList.remove('hidden')}finally{button.disabled=false}}

    el('connect').addEventListener('click',connect);el('token').addEventListener('keydown',event=>{if(event.key==='Enter')connect()});el('reload').addEventListener('click',loadItems);el('logout').addEventListener('click',()=>{localStorage.removeItem('jamoo_inventory_token');state.token='';el('token').value='';showLogin()});el('search').addEventListener('input',render);el('clear').addEventListener('click',()=>{el('search').value='';render()});el('content').addEventListener('click',event=>{const button=event.target.closest('[data-key]');if(button)openMovement(button.dataset.key,button.dataset.type)});el('type').addEventListener('change',applyType);el('cancelMovement').addEventListener('click',()=>el('movement').classList.add('hidden'));el('saveMovement').addEventListener('click',saveMovement);
    if(state.token){loadItems()}else{showLogin()}
    setInterval(()=>loadItems(true),3000);
  </script>
</body>
</html>''';

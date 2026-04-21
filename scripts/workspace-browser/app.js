(function () {
  "use strict";

  var WS_PREFIX = "/links/ws/";
  var API_SAVE = "/links/api/save";
  var API_READ = "/links/api/read";
  var API_MKDIR = "/links/api/mkdir";
  var FILES_JSON = "/links/files.json";
  var LS_SIDEBAR_W = "openclawLinksSidebarWidth";
  var searchDebounceTimer = null;

  var ROOT_PREFIX = (
    document.body.getAttribute("data-root-prefix") || ""
  ).replace(/\/+$/, "");

  /** Расширения и имена файлов, которые открываем как текст в редакторе */
  var EDIT_EXT =
    /\.(?:md|markdown|mdown|json|txt|yaml|yml|toml|sh|bash|zsh|fish|env|conf|cfg|ini|properties|css|less|scss|sass|js|mjs|cjs|jsx|ts|tsx|cts|mts|html|htm|svg|xml|gitignore|py|pyw|pyi|ipynb|rs|go|java|kt|kts|gradle|cpp|cc|cxx|h|hpp|hh|c|cs|php|rb|pl|pm|swift|vue|scala|sbt|clj|cljs|edn|ex|exs|erl|hrl|hs|lhs|lua|sql|r|dockerignore|gitattributes|editorconfig|lock)$/i;

  function isEditableText(rel) {
    var base = (rel.split("/").pop() || "").trim();
    if (/^(?:Dockerfile|Makefile|GNUmakefile|Jenkinsfile|Vagrantfile|Rakefile|Gemfile|Procfile)$/i.test(base))
      return true;
    return EDIT_EXT.test(rel);
  }

  function absPathFromRel(rel) {
    if (!rel) return ROOT_PREFIX || "";
    var norm = rel.replace(/^\/+/, "");
    if (!ROOT_PREFIX) return norm ? "/" + norm : "/";
    return ROOT_PREFIX + "/" + norm;
  }

  function dirname(rel) {
    var parts = rel.split("/").filter(Boolean);
    parts.pop();
    return parts.join("/");
  }

  function sanitizeUploadName(name) {
    var n = (name || "").replace(/\\/g, "/").split("/").pop() || "";
    if (!n || n === "." || n === ".." || /\//.test(name)) return null;
    if (n.indexOf("..") >= 0) return null;
    return n;
  }

  function sanitizeFolderName(name) {
    return sanitizeUploadName(name);
  }

  var editor = null;
  var currentPath = null;
  var apiToken = (localStorage.getItem("workspaceApiToken") || "").trim();
  var lastPathsFromServer = [];
  var extraPathsLocal = [];
  var focusedTreeLi = null;

  function encodePathSegments(rel) {
    return rel.split("/").filter(Boolean).map(encodeURIComponent).join("/");
  }

  function mergePathLists(server, extra) {
    var s = {};
    server.forEach(function (p) {
      s[p] = true;
    });
    extra.forEach(function (p) {
      s[p] = true;
    });
    return Object.keys(s).sort();
  }

  function buildTree(paths) {
    var root = { name: "", children: [], files: [] };
    paths.forEach(function (full) {
      var parts = full.split("/").filter(Boolean);
      var node = root;
      for (var i = 0; i < parts.length; i++) {
        var name = parts[i];
        var isLast = i === parts.length - 1;
        if (isLast) {
          node.files.push({ name: name, path: full });
        } else {
          var next = node.children.find(function (c) {
            return c.name === name;
          });
          if (!next) {
            next = { name: name, children: [], files: [] };
            node.children.push(next);
          }
          node = next;
        }
      }
    });
    function sortNode(n) {
      n.children.sort(function (a, b) {
        return a.name.localeCompare(b.name);
      });
      n.files.sort(function (a, b) {
        return a.name.localeCompare(b.name);
      });
      n.children.forEach(sortNode);
    }
    sortNode(root);
    return root;
  }

  function renderTree(node, depth, prefix) {
    depth = depth || 0;
    prefix = prefix || "";
    var ul = document.createElement("ul");
    ul.className = "tree-list";
    if (depth === 0) ul.classList.add("tree-root");

    node.children.forEach(function (child) {
      var dirPath = prefix ? prefix + "/" + child.name : child.name;
      var li = document.createElement("li");
      li.className = "tree-dir";
      li.setAttribute("data-tree-dir", dirPath);
      var label = document.createElement("span");
      label.className = "tree-label";
      label.tabIndex = -1;
      label.textContent = "📁 " + child.name;
      label.onclick = function (e) {
        e.stopPropagation();
        li.classList.toggle("open");
        setTreeFocus(li);
      };
      label.onmousedown = function (e) {
        e.preventDefault();
        label.focus();
        setTreeFocus(li);
      };
      li.appendChild(label);
      li.appendChild(renderTree(child, depth + 1, dirPath));
      ul.appendChild(li);
    });

    node.files.forEach(function (f) {
      var li = document.createElement("li");
      li.className = "tree-file";
      li.setAttribute("data-tree-file", f.path);
      var a = document.createElement("a");
      a.href = "#";
      a.tabIndex = -1;
      a.textContent = f.name;
      a.onclick = function (e) {
        e.preventDefault();
        setTreeFocus(li);
        openFile(f.path);
      };
      a.onmousedown = function (e) {
        e.preventDefault();
        a.focus();
        setTreeFocus(li);
      };
      li.appendChild(a);
      ul.appendChild(li);
    });

    return ul;
  }

  function findLiByFilePath(relPath) {
    var all = document.querySelectorAll("[data-tree-file]");
    for (var i = 0; i < all.length; i++) {
      if (all[i].getAttribute("data-tree-file") === relPath) return all[i];
    }
    return null;
  }

  /** Раскрыть цепочку каталогов до файла (после свёрнутого по умолчанию дерева). */
  function expandPathToFile(relPath) {
    var parts = relPath.split("/").filter(Boolean);
    for (var i = 0; i < parts.length - 1; i++) {
      var prefix = parts.slice(0, i + 1).join("/");
      var all = document.querySelectorAll("li.tree-dir[data-tree-dir]");
      for (var j = 0; j < all.length; j++) {
        if (all[j].getAttribute("data-tree-dir") === prefix) {
          all[j].classList.add("open");
          break;
        }
      }
    }
  }

  function clearTreeFocusClass() {
    var prev = document.querySelectorAll(".tree-row-focused");
    for (var i = 0; i < prev.length; i++) prev[i].classList.remove("tree-row-focused");
    focusedTreeLi = null;
  }

  function setTreeFocus(li) {
    if (!li || !li.classList) return;
    clearTreeFocusClass();
    li.classList.add("tree-row-focused");
    focusedTreeLi = li;
    li.scrollIntoView({ block: "nearest", behavior: "smooth" });
    updateUploadHint();
  }

  function visibleTreeRows() {
    var root = document.querySelector("#tree .tree-root");
    if (!root) return [];
    var rows = [];
    function walk(ul) {
      for (var i = 0; i < ul.children.length; i++) {
        var li = ul.children[i];
        if (li.classList.contains("tree-file")) {
          rows.push(li);
        } else if (li.classList.contains("tree-dir")) {
          rows.push(li);
          if (li.classList.contains("open")) {
            var inner = li.querySelector(":scope > ul.tree-list");
            if (inner) walk(inner);
          }
        }
      }
    }
    walk(root);
    return rows;
  }

  function focusTreeIndex(idx) {
    var rows = visibleTreeRows();
    if (!rows.length) return;
    var n = ((idx % rows.length) + rows.length) % rows.length;
    var li = rows[n];
    setTreeFocus(li);
    var t = li.querySelector("a, .tree-label");
    if (t) t.focus();
  }

  function currentFocusIndex() {
    var rows = visibleTreeRows();
    if (!focusedTreeLi) return -1;
    for (var i = 0; i < rows.length; i++) {
      if (rows[i] === focusedTreeLi) return i;
    }
    return -1;
  }

  function uploadTargetDir() {
    var li = focusedTreeLi || document.querySelector(".tree-row-focused");
    if (!li) return "";
    if (li.classList.contains("tree-file")) {
      var p = li.getAttribute("data-tree-file") || "";
      return dirname(p);
    }
    if (li.classList.contains("tree-dir")) {
      return li.getAttribute("data-tree-dir") || "";
    }
    return "";
  }

  function updateUploadHint() {
    var d = uploadTargetDir();
    var line = d
      ? "Загрузка в: ~/" + d + "/"
      : "Загрузка в корень ~ (выберите папку или файл в дереве стрелками)";
    var el = document.getElementById("upload-target-hint");
    var elTb = document.getElementById("toolbar-upload-hint");
    if (el) el.textContent = line;
    if (elTb) elTb.textContent = line;
  }

  function utf8FromBinaryString(bin) {
    try {
      if (typeof TextDecoder !== "undefined")
        return new TextDecoder("utf-8", { fatal: false }).decode(
          Uint8Array.from(bin, function (c) {
            return c.charCodeAt(0) & 0xff;
          })
        );
    } catch (ignore) {}
    var out = "";
    for (var i = 0; i < bin.length; i++)
      out += String.fromCharCode(bin.charCodeAt(i) & 0xff);
    return out;
  }

  function fetchFileViaApi(relPath) {
    return ensureApiToken().then(function (tok) {
      if (!tok)
        throw new Error(
          "403 — введите API-токен: без него Caddy не отдаёт файл, чтение идёт через API"
        );
      return fetch(API_READ, {
        method: "POST",
        headers: {
          "Content-Type": "application/json; charset=utf-8",
          "X-Api-Token": tok,
        },
        body: JSON.stringify({ relativePath: relPath }),
      }).then(function (r) {
        return r.text().then(function (text) {
          var j = null;
          try {
            j = text ? JSON.parse(text) : null;
          } catch (ignore) {}
          if (r.ok && j && j.ok && typeof j.content === "string") {
            if (j.encoding === "base64") return utf8FromBinaryString(atob(j.content));
            return j.content;
          }
          if (j && j.error === "unauthorized") {
            localStorage.removeItem("workspaceApiToken");
            apiToken = "";
          }
          var msg = (j && j.error) || text.slice(0, 120) || String(r.status);
          throw new Error(msg);
        });
      });
    });
  }

  function fetchFileText(relPath) {
    return fetch(WS_PREFIX + encodePathSegments(relPath), { cache: "no-store" }).then(
      function (r) {
        if (r.ok) return r.text();
        if (r.status === 403 || r.status === 401) return fetchFileViaApi(relPath);
        throw new Error(r.status);
      }
    );
  }

  function onSidebarKeydown(e) {
    var side = document.getElementById("sidebar-tree");
    if (!side || !side.contains(document.activeElement)) return;
    var ed = document.getElementById("editor-host");
    if (ed && ed.contains(document.activeElement)) return;

    var key = e.key;
    if (
      key !== "ArrowUp" &&
      key !== "ArrowDown" &&
      key !== "ArrowLeft" &&
      key !== "ArrowRight" &&
      key !== "Enter"
    )
      return;

    var rows = visibleTreeRows();
    if (!rows.length) return;

    e.preventDefault();
    var idx = currentFocusIndex();
    if (key === "ArrowDown") {
      if (idx < 0) focusTreeIndex(0);
      else focusTreeIndex(idx + 1);
      return;
    }
    if (key === "ArrowUp") {
      if (idx < 0) focusTreeIndex(rows.length - 1);
      else focusTreeIndex(idx - 1);
      return;
    }
    var li = focusedTreeLi || rows[0];
    if (key === "ArrowRight") {
      if (li.classList.contains("tree-dir") && !li.classList.contains("open")) {
        li.classList.add("open");
      }
      return;
    }
    if (key === "ArrowLeft") {
      if (li.classList.contains("tree-dir") && li.classList.contains("open")) {
        li.classList.remove("open");
      }
      return;
    }
    if (key === "Enter") {
      if (li.classList.contains("tree-dir")) {
        li.classList.toggle("open");
        return;
      }
      if (li.classList.contains("tree-file")) {
        var p = li.getAttribute("data-tree-file");
        if (p) openFile(p);
      }
    }
  }

  function cmModeForPath(rel) {
    var lower = rel.toLowerCase();
    if (/\.(md|markdown|mdown)$/.test(lower)) return "markdown";
    if (/\.json$/.test(lower)) return { name: "javascript", json: true };
    if (/\.ipynb$/.test(lower)) return { name: "javascript", json: true };
    if (/\.ya?ml$/.test(lower)) return "yaml";
    if (/\.(html|htm|svg)$/.test(lower)) return "htmlmixed";
    if (/\.(xml)$/.test(lower)) return "xml";
    if (/\.(css|less|scss|sass)$/.test(lower)) return "css";
    if (/\.(js|mjs|cjs|jsx|ts|tsx|cts|mts)$/.test(lower)) return "javascript";
    if (/\.(py|pyw|pyi)$/.test(lower)) return "python";
    return "text/plain";
  }

  function destroyEditor() {
    if (editor && editor.toTextArea) {
      editor.toTextArea();
    }
    editor = null;
    var ta = document.getElementById("editor-host");
    ta.innerHTML = "";
    var t = document.createElement("textarea");
    t.id = "code";
    ta.appendChild(t);
  }

  function setDownloadLink(relPath) {
    var a = document.getElementById("btn-download");
    var url = WS_PREFIX + encodePathSegments(relPath);
    a.href = url;
    var base = relPath.split("/").filter(Boolean).pop() || "file";
    a.setAttribute("download", base);
    a.setAttribute("title", url);
  }

  function openFile(relPath) {
    currentPath = relPath;
    document.getElementById("current-file").textContent = absPathFromRel(relPath);

    var toolbar = document.getElementById("editor-toolbar");
    var editRow = document.getElementById("editor-edit-row");
    var actionsRow = document.getElementById("editor-toolbar-actions");
    toolbar.style.display = "flex";
    if (actionsRow) actionsRow.style.display = "flex";
    setDownloadLink(relPath);

    var editable = isEditableText(relPath);
    editRow.style.display = editable ? "flex" : "none";

    expandPathToFile(relPath);
    var li = findLiByFilePath(relPath);
    if (li) setTreeFocus(li);

    if (!editable) {
      destroyEditor();
      document.getElementById("editor-host").innerHTML =
        '<p class="muted">Редактор для этого типа не включён (бинарный или нестандартный формат). Скачайте файл кнопкой «Скачать» выше.</p>';
      return;
    }

    fetchFileText(relPath)
      .then(function (text) {
        destroyEditor();
        var ta = document.querySelector("#editor-host textarea");
        ta.value = text;
        editor = CodeMirror.fromTextArea(ta, {
          lineNumbers: true,
          mode: cmModeForPath(relPath),
          theme: "default",
          lineWrapping: true,
        });
        editor.setSize("100%", "100%");
      })
      .catch(function (e) {
        document.getElementById("editor-host").innerHTML =
          '<p class="error">Не удалось загрузить: ' +
          String(e.message || e) +
          "</p><p class=\"muted\" style=\"margin-top:0.5rem\">Если был код 403 с веб-сервера, введите API-токен при запросе — тогда текст подставится через /links/api/read.</p>";
      });
  }

  function getEditorText() {
    if (editor && editor.getValue) return editor.getValue();
    var ta = document.querySelector("#editor-host textarea");
    return ta ? ta.value : "";
  }

  function promptApiToken() {
    return (window.prompt(
      "Введите API-токен (одна строка из ~/.openclaw/.workspace-api-token на сервере, без кавычек):"
    ) || "").trim();
  }

  function ensureApiToken() {
    if (apiToken.trim()) return Promise.resolve(apiToken.trim());
    var t = promptApiToken();
    if (!t) return Promise.resolve("");
    apiToken = t;
    localStorage.setItem("workspaceApiToken", apiToken);
    return Promise.resolve(apiToken);
  }

  function postMkdir(bodyObj) {
    return ensureApiToken().then(function (tok) {
      if (!tok) return Promise.resolve({ ok: false, skip: true });
      return fetch(API_MKDIR, {
        method: "POST",
        headers: {
          "Content-Type": "application/json; charset=utf-8",
          "X-Api-Token": tok,
        },
        body: JSON.stringify(bodyObj),
      }).then(function (r) {
        return r.text().then(function (text) {
          var j = null;
          try {
            j = text ? JSON.parse(text) : null;
          } catch (ignore) {}
          return { ok: r.ok, status: r.status, j: j, raw: text };
        });
      });
    });
  }

  function postSave(bodyObj) {
    return ensureApiToken().then(function (tok) {
      if (!tok) return Promise.resolve({ ok: false, skip: true });
      return fetch(API_SAVE, {
        method: "POST",
        headers: {
          "Content-Type": "application/json; charset=utf-8",
          "X-Api-Token": tok,
        },
        body: JSON.stringify(bodyObj),
      }).then(function (r) {
        return r.text().then(function (text) {
          var j = null;
          try {
            j = text ? JSON.parse(text) : null;
          } catch (ignore) {}
          return { ok: r.ok, status: r.status, j: j, raw: text };
        });
      });
    });
  }

  function saveFile() {
    if (!currentPath) return;
    if (!isEditableText(currentPath)) return;
    postSave({
      relativePath: currentPath,
      content: getEditorText(),
    })
      .then(function (x) {
        if (x.skip) return;
        if (x.ok && x.j && x.j.ok) {
          document.getElementById("save-status").textContent =
            "Сохранено " + new Date().toLocaleTimeString();
          return;
        }
        if (x.j && x.j.error === "unauthorized") {
          localStorage.removeItem("workspaceApiToken");
          apiToken = "";
        }
        var msg =
          (x.j && x.j.error) ||
          (x.raw && x.raw.slice(0, 120)) ||
          "save failed";
        document.getElementById("save-status").textContent =
          "Ошибка HTTP " + x.status + ": " + msg;
      })
      .catch(function (e) {
        document.getElementById("save-status").textContent = String(e);
      });
  }

  function fileToBase64(file) {
    return new Promise(function (resolve, reject) {
      var r = new FileReader();
      r.onload = function () {
        var s = r.result;
        var i = typeof s === "string" ? s.indexOf(",") : -1;
        resolve(i >= 0 ? s.slice(i + 1) : s);
      };
      r.onerror = function () {
        reject(r.error);
      };
      r.readAsDataURL(file);
    });
  }

  function runUpload(files) {
    var hint = document.getElementById("upload-target-hint");
    if (!files || !files.length) return;
    var base = uploadTargetDir();
    hint.textContent = "Загрузка…";
    var tasks = [];
    for (var i = 0; i < files.length; i++) {
      (function (file) {
        var name = sanitizeUploadName(file.name);
        if (!name) {
          tasks.push(Promise.resolve({ ok: false, err: "bad name: " + file.name }));
          return;
        }
        var rel = base ? base + "/" + name : name;
        tasks.push(
          fileToBase64(file).then(function (b64) {
            return postSave({
              relativePath: rel,
              content: b64,
              encoding: "base64",
            }).then(function (x) {
              if (x.skip) return { ok: false, err: "no token" };
              if (x.ok && x.j && x.j.ok) {
                if (extraPathsLocal.indexOf(rel) < 0) extraPathsLocal.push(rel);
                return { ok: true, rel: rel };
              }
              var msg = (x.j && x.j.error) || x.raw || "failed";
              return { ok: false, err: msg };
            });
          })
        );
      })(files[i]);
    }
    Promise.all(tasks)
      .then(function (results) {
        var ok = results.filter(function (r) {
          return r && r.ok;
        });
        var bad = results.filter(function (r) {
          return r && !r.ok;
        });
        if (ok.length) {
          rebuildTreeFromMerged();
          var first = ok[0].rel;
          if (first) openFile(first);
        }
        hint.textContent =
          ok.length +
          " ок" +
          (bad.length ? ", ошибок: " + bad.length + " (" + (bad[0].err || "") + ")" : "");
        if (bad.length && bad[0].err === "unauthorized") {
          hint.textContent += " — проверьте токен.";
        }
      })
      .catch(function (e) {
        hint.textContent = String(e);
      });
  }

  function getMergedPaths() {
    return mergePathLists(lastPathsFromServer, extraPathsLocal);
  }

  function applySearch() {
    var input = document.getElementById("tree-search");
    var meta = document.getElementById("tree-search-meta");
    var resHost = document.getElementById("tree-search-results");
    var treeHost = document.getElementById("tree");
    if (!input || !treeHost || !resHost) return;
    var q = (input.value || "").trim().toLowerCase();
    if (!q) {
      treeHost.style.display = "";
      resHost.innerHTML = "";
      resHost.style.display = "none";
      if (meta) meta.textContent = "";
      return;
    }
    var paths = getMergedPaths();
    var hits = [];
    for (var i = 0; i < paths.length; i++) {
      if (paths[i].toLowerCase().indexOf(q) >= 0) hits.push(paths[i]);
      if (hits.length >= 400) break;
    }
    treeHost.style.display = "none";
    resHost.style.display = "block";
    resHost.innerHTML = "";
    var ul = document.createElement("ul");
    ul.className = "search-results";
    hits.forEach(function (p) {
      var li = document.createElement("li");
      var a = document.createElement("a");
      a.href = "#";
      a.textContent = p;
      a.onclick = function (e) {
        e.preventDefault();
        input.value = "";
        applySearch();
        openFile(p);
      };
      li.appendChild(a);
      ul.appendChild(li);
    });
    resHost.appendChild(ul);
    if (meta)
      meta.textContent =
        hits.length + " совпад." + (hits.length >= 400 ? " (показаны первые 400)" : "");
  }

  function scheduleSearch() {
    if (searchDebounceTimer) clearTimeout(searchDebounceTimer);
    searchDebounceTimer = setTimeout(function () {
      searchDebounceTimer = null;
      applySearch();
    }, 200);
  }

  function rebuildTreeFromMerged() {
    var paths = getMergedPaths();
    var tree = buildTree(paths);
    var host = document.getElementById("tree");
    host.innerHTML = "";
    host.appendChild(renderTree(tree, 0, ""));
    updateUploadHint();
    var input = document.getElementById("tree-search");
    if (input && (input.value || "").trim()) applySearch();
  }

  function initSidebarResize() {
    var split = document.getElementById("sidebar-splitter");
    var side = document.getElementById("sidebar-tree");
    if (!split || !side) return;
    var w = parseInt(localStorage.getItem(LS_SIDEBAR_W), 10);
    if (w >= 160 && w <= 2400) side.style.width = w + "px";

    split.addEventListener("mousedown", function (e) {
      if (e.button !== 0) return;
      e.preventDefault();
      split.classList.add("is-dragging");
      var startX = e.clientX;
      var startW = side.getBoundingClientRect().width;
      function move(ev) {
        var nw = Math.max(
          160,
          Math.min(window.innerWidth - 120, startW + ev.clientX - startX)
        );
        side.style.width = Math.round(nw) + "px";
      }
      function up() {
        split.classList.remove("is-dragging");
        document.removeEventListener("mousemove", move);
        document.removeEventListener("mouseup", up);
        localStorage.setItem(
          LS_SIDEBAR_W,
          String(Math.round(side.getBoundingClientRect().width))
        );
      }
      document.addEventListener("mousemove", move);
      document.addEventListener("mouseup", up);
    });
  }

  function loadFiles() {
    fetch(FILES_JSON + "?r=" + Date.now(), { cache: "no-store" })
      .then(function (r) {
        return r.json();
      })
      .then(function (paths) {
        lastPathsFromServer = paths;
        rebuildTreeFromMerged();
      })
      .catch(function (e) {
        document.getElementById("tree").innerHTML =
          '<p class="error">Не загружен files.json: ' + String(e) + "</p>";
      });
  }

  document.getElementById("btn-refresh-tree").onclick = function () {
    var u = location.pathname.endsWith("/") ? location.pathname : location.pathname + "/";
    location.replace(location.origin + u + "?r=" + Date.now());
  };

  document.getElementById("btn-save").onclick = saveFile;
  document.getElementById("btn-clear-token").onclick = function () {
    localStorage.removeItem("workspaceApiToken");
    apiToken = "";
    document.getElementById("save-status").textContent =
      "Токен сброшен. При следующем «Сохранить» вставьте строку из ~/.openclaw/.workspace-api-token";
  };

  document.getElementById("btn-upload").onclick = function () {
    document.getElementById("file-upload").click();
  };

  document.getElementById("file-upload").onchange = function (e) {
    var files = e.target.files;
    runUpload(files);
    e.target.value = "";
  };

  var treeSearch = document.getElementById("tree-search");
  if (treeSearch) {
    treeSearch.addEventListener("input", scheduleSearch);
    treeSearch.addEventListener("search", function () {
      scheduleSearch();
    });
  }

  document.getElementById("btn-mkdir").onclick = function () {
    var base = uploadTargetDir();
    var hint = base ? "~/" + base + "/" : "~/";
    var raw = window.prompt("Имя новой папки (будет создана в " + hint + "):", "");
    var name = sanitizeFolderName(raw);
    if (!name) {
      if (raw && String(raw).trim()) window.alert("Недопустимое имя папки.");
      return;
    }
    var rel = base ? base + "/" + name : name;
    var hintEl = document.getElementById("upload-target-hint");
    if (hintEl) hintEl.textContent = "Создание папки…";
    postMkdir({ relativePath: rel })
      .then(function (x) {
        if (x.skip) {
          if (hintEl) updateUploadHint();
          return;
        }
        if (x.ok && x.j && x.j.ok) {
          var keep = x.j.keepRelative;
          var keepPath = keep || rel + "/.keep";
          if (keepPath && extraPathsLocal.indexOf(keepPath) < 0)
            extraPathsLocal.push(keepPath);
          rebuildTreeFromMerged();
          expandPathToFile(keepPath);
          var li = findLiByFilePath(keepPath);
          if (li) setTreeFocus(li);
          if (hintEl) hintEl.textContent = "Папка создана: ~/" + rel + "/";
          return;
        }
        if (x.j && x.j.error === "unauthorized") {
          localStorage.removeItem("workspaceApiToken");
          apiToken = "";
        }
        if (hintEl)
          hintEl.textContent =
            "Ошибка: " + ((x.j && x.j.error) || x.raw || x.status);
      })
      .catch(function (e) {
        if (hintEl) hintEl.textContent = String(e);
      });
  };

  var sidebarTree = document.getElementById("sidebar-tree");
  if (sidebarTree) {
    sidebarTree.addEventListener("keydown", onSidebarKeydown);
  }

  initSidebarResize();
  loadFiles();
  updateUploadHint();
})();

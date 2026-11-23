import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["images", "archive", "imageInput", "previews", "clearButton", "archiveName", "error"];
  static values = { maxBytes: Number, maxRequestBytes: Number };

  connect() {
    this.urls = [];
    this.showJavascriptControls();
    this.switchMode();
    this.preview();
    this.element.dataset.ready = "true";
    document.getElementById("server-error")?.focus();
  }

  disconnect() {
    this.release();
    delete this.element.dataset.ready;
  }

  showJavascriptControls() {
    this.element.querySelectorAll("[data-javascript-control]").forEach(control => { control.hidden = false; });
  }

  switchMode() {
    const archive = this.element.querySelector('[name="input_mode"]:checked').value === "archive";
    this.imagesTarget.hidden = archive;
    this.imagesTarget.disabled = archive;
    this.archiveTarget.hidden = !archive;
    this.archiveTarget.disabled = !archive;
    this.clearError();
  }

  clearImages() {
    this.imageInputTarget.value = "";
    this.imagesChanged();
    this.imageInputTarget.focus();
  }

  imagesChanged() {
    this.preview();
    this.clearError();
  }

  allowDrop(event) {
    if (this.imagesTarget.disabled || !Array.from(event.dataTransfer?.types || []).includes("Files")) {
      return;
    }

    event.preventDefault();
    event.dataTransfer.dropEffect = "copy";
  }

  appendDroppedFiles(event) {
    if (this.imagesTarget.disabled || !Array.from(event.dataTransfer?.types || []).includes("Files")) {
      return;
    }

    event.preventDefault();

    const dropped = Array.from(event.dataTransfer.files);

    if (!dropped.length) {
      return;
    }

    this.setImages([...this.imageInputTarget.files, ...dropped]);
  }

  setImages(files) {
    const selection = new DataTransfer();
    files.forEach(file => selection.items.add(file));
    this.imageInputTarget.files = selection.files;
    this.imagesChanged();
  }

  removeImage(event) {
    const index = Number(event.currentTarget.dataset.index);
    this.setImages(Array.from(this.imageInputTarget.files).filter((_file, position) => position !== index));
    const buttons = this.previewsTarget.querySelectorAll("button");
    (buttons[Math.min(index, buttons.length - 1)] || this.imageInputTarget).focus();
  }

  preview() {
    this.release();
    this.previewsTarget.replaceChildren();
    this.clearButtonTarget.disabled = this.imageInputTarget.files.length === 0;

    Array.from(this.imageInputTarget.files).forEach((file, index) => {
      const figure = document.createElement("figure");
      figure.className = "max-w-40 break-all text-xs text-slate-600";

      if (/\.(png|gif)$/i.test(file.name)) {
        const url = URL.createObjectURL(file);
        this.urls.push(url);
        const image = document.createElement("img");
        image.src = url;
        image.alt = `Preview of ${file.name}`;
        image.className = "mb-1 h-16 w-16 rounded border border-slate-200 object-contain";
        figure.append(image);
      }

      const name = document.createElement("figcaption");
      name.textContent = file.name;
      figure.append(name);

      const remove = document.createElement("button");
      remove.type = "button";
      remove.textContent = "Remove";
      remove.setAttribute("aria-label", `Remove ${file.name}`);
      remove.dataset.action = "upload#removeImage";
      remove.dataset.index = String(index);
      remove.className = "mt-1 block rounded-md border border-red-200 bg-red-50 px-2 py-1 text-xs font-medium text-red-800 hover:bg-red-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-600";
      name.append(remove);

      this.previewsTarget.append(figure);
    });
  }

  release() {
    this.urls.forEach(url => URL.revokeObjectURL(url));
    this.urls = [];
  }

  archiveChanged(event) {
    this.archiveNameTarget.textContent = event.target.files[0]?.name || "";
    this.clearError();
  }

  clearError() {
    this.errorTarget.hidden = true;
    this.errorTarget.textContent = "";
  }

  validate(event) {
    this.clearError();

    const archive = !this.archiveTarget.disabled;
    const files = archive ? Array.from(this.archiveTarget.querySelector("input").files) :
      Array.from(this.imageInputTarget.files);
    let error;

    if (!files.length) error = "No file(s) selected.";
    else if (archive && !/\.zip$/i.test(files[0].name)) error = "Select a ZIP archive.";
    else if (!archive && files.some(file => !/\.(png|gif)$/i.test(file.name))) error = "Only PNG and static GIF images are supported.";
    else if (!archive && files.reduce((total, file) => total + file.size, 0) > this.maxBytesValue) error = "Image uploads exceed the 32 MiB total.";
    else if (archive && files[0].size > this.maxRequestBytesValue) error = "The ZIP file exceeds the 40 MiB request limit.";

    if (error) {
      event.preventDefault();
      this.errorTarget.textContent = error;
      this.errorTarget.hidden = false;
      this.errorTarget.focus();
    }
  }
}

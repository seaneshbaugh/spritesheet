import { Application } from "@hotwired/stimulus";
import UploadController from "upload-controller";

const application = Application.start();
application.register("upload", UploadController);

import React, { Component } from "react";
import shajs from "sha.js";
import ToggleSwitch from "./Form/ToggleSwitch.jsx";
import ImageInputs from "./Form/ImageInputs.jsx";
import ArchiveInput from "./Form/ArchiveInput.jsx";
import AdvancedOptions from "./Form/AdvancedOptions.jsx";

class Form extends Component {
  constructor(props) {
    super(props);

    this.state = {
      useArchive: false,
      showAdvancedOptions: false,
      imageFiles: [{ id: this.getNewImageID() }],
      archiveFile: null
    };

    this.handleClickInputToggle = this.handleClickInputToggle.bind(this);
    this.handleClickAdvancedOptionsToggle = this.handleClickAdvancedOptionsToggle.bind(this);
    this.addImage = this.addImage.bind(this);
    this.updateImage = this.updateImage.bind(this);
    this.removeImage = this.removeImage.bind(this);
  }

  handleClickInputToggle(_event) {
    this.setState({
      useArchive: !this.state.useArchive
    });
  }

  handleClickAdvancedOptionsToggle(_event) {
    this.setState({
      showAdvancedOptions: !this.state.showAdvancedOptions
    });
  }

  addImage() {
    const updatedImageFiles = this.state.imageFiles.slice();

    updatedImageFiles.push({ id: this.getNewImageID() });

    this.setState({
      imageFiles: updatedImageFiles
    });
  }

  updateImage(index, file) {
    const updatedImageFiles = this.state.imageFiles.slice();

    file.id = updatedImageFiles[index].id;

    updatedImageFiles[index] = file;

    this.setState({
      imageFiles: updatedImageFiles
    });
  }

  removeImage(index) {
    const updatedImageFiles = this.state.imageFiles.slice();

    updatedImageFiles.splice(index, 1);

    if (updatedImageFiles.length === 0) {
      updatedImageFiles.push(null);
    }

    this.setState({
      imageFiles: updatedImageFiles
    });
  }

  getNewImageID() {
    return shajs("sha256").update((new Date()).toString()).digest("hex");
  }

  render() {
    let advancedOptions;

    if (this.state.showAdvancedOptions) {
      advancedOptions = <AdvancedOptions/>;
    }

    return (
      <form className="file-upload-form" action="/" method="POST" encType="multipart/form-data" role="form">
        <div className="row">
          <div className="col s12">
            <ToggleSwitch offText="Images" onText="Archive" onClick={this.handleClickInputToggle}/>
          </div>
        </div>
        <ArchiveInput archiveFile={this.state.archiveFile} disabled={!this.state.useArchive}/>
        <ImageInputs imageFiles={this.state.imageFiles} onClickAddImage={this.addImage} onChangeImage={this.updateImage} onClickRemoveImage={this.removeImage} disabled={this.state.useArchive}/>
        <br/>
        <div className="row">
          <div className="col s12">
            Advanced Options<br/>
            <ToggleSwitch offText="Hide" onText="Show" onClick={this.handleClickAdvancedOptionsToggle}/>
          </div>
          <div className="col s12">
            {advancedOptions}
          </div>
        </div>
        <div className="row">
          <div className="col s12">
            <button className="submit-button waves-effect waves-light btn">Submit</button>
          </div>
        </div>
      </form>
    );
  }
}

export default Form;

import React, { Component } from "react";

class ImageInput extends Component {
  constructor(props) {
    super(props);

    this.handleChangeImage = this.handleChangeImage.bind(this);
    this.handleClickRemoveImage = this.handleClickRemoveImage.bind(this);
  }

  handleChangeImage(event) {
    if (event.target.files[0]) {
      this.props.onChangeImage(event.target.files[0]);
    } else {
      this.props.onChangeImage({ id: this.props.file.id });
    }
  }

  handleClickRemoveImage(event) {
    event.preventDefault();

    this.props.onClickRemoveImage();
  }

  render() {
    let selectedText, preview, remove;

    if (this.props.file.name) {
      selectedText = `Selected file: ${this.props.file.name}`;

      const revoke = (event) => (URL.revokeObjectURL(event.target.src));

      preview = <img src={URL.createObjectURL(this.props.file)} onLoad={revoke}/>;

      remove = <button className="remove-image waves-effect waves-light btn" onClick={this.handleClickRemoveImage}>&times;</button>;
    }

    return (
      <div className="image-input row">
        <label className="col s3">
          <span className="image-input-label waves-effect waves-light btn">Select File</span>
          <input name={`image_files[${this.props.file.id}`} type="file" accept="image" style={{ display: "none" }} onChange={this.handleChangeImage} disabled={this.props.disabled}/>
        </label>
        <div className="image-file-name col s3">
          {selectedText}
        </div>
        <div className="image-preview col s3">
          {preview}
        </div>
        <div className="col s1">
          {remove}
        </div>
      </div>
    );
  }
}

export default ImageInput;
